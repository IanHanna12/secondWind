import Foundation
import SecondWindCore

/// Adds explainable application relationships to already-observed storage.
/// It never changes an entry's risk or cleanup eligibility.
public struct ApplicationAssociationResolver: @unchecked Sendable, ApplicationAssociationResolving {
    private let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home.standardizedFileURL
    }

    public func resolve(inventory: StorageInventory, applications: [InstalledApplication]) -> StorageInventory {
        let installedIdentifiers = Set(applications.compactMap(\.bundleIdentifier))
        let resolvedEntries = inventory.entries.map { entry in
            resolve(
                entry: entry,
                applications: applications,
                installedIdentifiers: installedIdentifiers
            )
        }
        return StorageInventory(capturedAt: inventory.capturedAt, entries: resolvedEntries)
    }

    private func resolve(
        entry: StorageInventoryEntry,
        applications: [InstalledApplication],
        installedIdentifiers: Set<String>
    ) -> StorageInventoryEntry {
        guard let path = entry.path else { return entry }

        let associations = resolvedAssociations(
            for: entry,
            at: path,
            applications: applications,
            installedIdentifiers: installedIdentifiers
        )
        guard associations != entry.applicationAssociations else { return entry }
        return entry.withApplicationAssociations(associations)
    }

    private func resolvedAssociations(
        for entry: StorageInventoryEntry,
        at path: String,
        applications: [InstalledApplication],
        installedIdentifiers: Set<String>
    ) -> [ApplicationAssociation] {
        var associations = entry.applicationAssociations

        for application in applications {
            guard let relationship = relationship(for: path, entry: entry, application: application) else { continue }
            let association = ApplicationAssociation(
                application: ApplicationIdentity(application: application),
                relationship: relationship,
                reason: reason(for: relationship, application: application),
                evidence: relationship == .application ? .exact : .knownPath
            )
            if !associations.contains(where: { $0.id == association.id }) {
                associations.append(association)
            }
        }

        if associations.isEmpty,
           let orphan = orphanAssociation(for: path, excluding: installedIdentifiers) {
            associations.append(orphan)
        }
        return associations
    }

    private func relationship(for path: String, entry: StorageInventoryEntry, application: InstalledApplication) -> ApplicationStorageRelationship? {
        let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
        if standardizedPath == application.url.path { return .application }
        guard let identifier = application.bundleIdentifier else { return developerRelationship(for: entry, application: application) }

        for candidate in knownPaths(for: identifier) where isSameOrDescendant(standardizedPath, of: candidate.url.path) {
            return candidate.relationship
        }
        return developerRelationship(for: entry, application: application)
    }

    private func developerRelationship(for entry: StorageInventoryEntry, application: InstalledApplication) -> ApplicationStorageRelationship? {
        guard application.bundleIdentifier == "com.apple.dt.Xcode" else { return nil }
        let path = entry.path ?? ""
        let isKnownXcodeLocation = entry.key.contains("xcode-") ||
            path.contains("/Library/Developer/Xcode/") ||
            path.contains("/Library/Developer/CoreSimulator/")
        return isKnownXcodeLocation ? .developerData : nil
    }

    private func reason(for relationship: ApplicationStorageRelationship, application: InstalledApplication) -> String {
        switch relationship {
        case .application: return "Associated by the installed application bundle path."
        case .developerData: return "Associated by a built-in Xcode developer-storage rule."
        default:
            let identifier = application.bundleIdentifier ?? "unavailable"
            return "Associated by a known \(relationship.title.lowercased()) path for bundle identifier \(identifier)."
        }
    }

    private func orphanAssociation(for path: String, excluding installedIdentifiers: Set<String>) -> ApplicationAssociation? {
        guard let candidate = orphanCandidate(for: path), !installedIdentifiers.contains(candidate.identifier) else { return nil }
        return ApplicationAssociation(
            application: ApplicationIdentity(orphanBundleIdentifier: candidate.identifier),
            relationship: candidate.relationship,
            reason: "Associated by a bundle-identifier-shaped path, but no installed application with that identifier was found.",
            evidence: .possibleOrphan
        )
    }

    private func orphanCandidate(for path: String) -> (identifier: String, relationship: ApplicationStorageRelationship)? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let parent = url.deletingLastPathComponent().path
        let name = url.lastPathComponent
        let library = home.appendingPathComponent("Library")
        let candidates: [(URL, ApplicationStorageRelationship)] = [
            (library.appendingPathComponent("Application Support"), .supportData),
            (library.appendingPathComponent("Caches"), .cache),
            (library.appendingPathComponent("Logs"), .logs),
            (library.appendingPathComponent("Containers"), .container),
            (library.appendingPathComponent("Saved Application State"), .savedApplicationState)
        ]
        if let match = candidates.first(where: { $0.0.path == parent }) {
            let identifier = match.1 == .savedApplicationState
                ? name.replacingOccurrences(of: ".savedState", with: "")
                : name
            return isBundleIdentifier(identifier) ? (identifier, match.1) : nil
        }
        let preferences = library.appendingPathComponent("Preferences")
        guard parent == preferences.path, name.hasSuffix(".plist") else { return nil }
        let identifier = String(name.dropLast(".plist".count))
        return isBundleIdentifier(identifier) ? (identifier, .preferences) : nil
    }

    private func knownPaths(for identifier: String) -> [(url: URL, relationship: ApplicationStorageRelationship)] {
        let library = home.appendingPathComponent("Library")
        return [
            (library.appendingPathComponent("Application Support/\(identifier)"), .supportData),
            (library.appendingPathComponent("Caches/\(identifier)"), .cache),
            (library.appendingPathComponent("Logs/\(identifier)"), .logs),
            (library.appendingPathComponent("Preferences/\(identifier).plist"), .preferences),
            (library.appendingPathComponent("Saved Application State/\(identifier).savedState"), .savedApplicationState),
            (library.appendingPathComponent("Containers/\(identifier)"), .container)
        ]
    }

    private func isSameOrDescendant(_ path: String, of root: String) -> Bool {
        path == root || path.hasPrefix(root + "/")
    }

    private func isBundleIdentifier(_ value: String) -> Bool {
        let components = value.split(separator: ".")
        return components.count >= 2 && components.allSatisfy { component in
            component.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
}

/// Observes a deliberately small set of exact, identifier-based application
/// paths. Storage for installed apps stays protected. A path with no matching
/// installed app can become a review-required cleanup finding.
public struct ApplicationStorageObserver: @unchecked Sendable {
    private let home: URL
    private let fileManager: FileManager
    private let fileSystem: LocalFileSystem

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager: FileManager = .default) {
        self.home = home.standardizedFileURL
        self.fileManager = fileManager
        fileSystem = LocalFileSystem(fileManager: fileManager)
    }

    public func entries(for applications: [InstalledApplication]) -> [StorageInventoryEntry] {
        let installedIdentifiers = Set(applications.compactMap(\.bundleIdentifier))
        let installedEntries = applications.flatMap { application in
            guard let identifier = application.bundleIdentifier else { return [StorageInventoryEntry]() }
            return knownPaths(for: identifier).compactMap { candidate in
                guard fileManager.fileExists(atPath: candidate.url.path) else { return nil }
                return StorageInventoryEntry(
                    key: "application-storage|\(candidate.relationship.rawValue)|\(candidate.url.path)",
                    title: "\(candidate.relationship.title): \(application.displayName)",
                    path: candidate.url.path,
                    category: category(for: candidate.relationship),
                    byteSize: fileSystem.fileSize(at: candidate.url),
                    origin: "Known application storage path",
                    explanation: "Observed locally at an exact \(candidate.relationship.title.lowercased()) path for \(identifier). This observation does not itself make the item eligible for cleanup.",
                    risk: .protected,
                    isActionable: false,
                    modifiedAt: modificationDate(at: candidate.url)
                )
            }
        }
        return installedEntries + orphanCandidateEntries(excluding: installedIdentifiers)
    }

    /// Turns exact bundle-identifier paths without a matching installed app
    /// into review-required findings. They enter the normal plan workflow and
    /// therefore default to Recovery instead of being changed during a scan.
    public func orphanCleanupFindings(for applications: [InstalledApplication]) -> [Finding] {
        let installedIdentifiers = Set(applications.compactMap(\.bundleIdentifier))
        return orphanCandidates(excluding: installedIdentifiers).map { candidate in
            Finding(
                ruleID: "orphaned-application-storage",
                ruleVersion: BuiltInRules.version,
                title: "Possible orphan: \(candidate.identifier)",
                path: candidate.url.path,
                byteSize: fileSystem.fileSize(at: candidate.url),
                category: findingCategory(for: candidate.relationship),
                origin: "Orphaned application storage",
                explanation: "No installed application with bundle identifier \(candidate.identifier) was found at this exact \(candidate.relationship.title.lowercased()) path. Review it before moving it; Recovery is the default destination.",
                risk: .reviewRequired,
                supportedAction: .cleanup,
                confidence: .needsUserReview
            )
        }
    }

    private func knownPaths(for identifier: String) -> [(url: URL, relationship: ApplicationStorageRelationship)] {
        let library = home.appendingPathComponent("Library")
        return [
            (library.appendingPathComponent("Application Support/\(identifier)"), .supportData),
            (library.appendingPathComponent("Caches/\(identifier)"), .cache),
            (library.appendingPathComponent("Logs/\(identifier)"), .logs),
            (library.appendingPathComponent("Preferences/\(identifier).plist"), .preferences),
            (library.appendingPathComponent("Saved Application State/\(identifier).savedState"), .savedApplicationState),
            (library.appendingPathComponent("Containers/\(identifier)"), .container)
        ]
    }

    private func category(for relationship: ApplicationStorageRelationship) -> StorageCategory {
        switch relationship {
        case .cache: return .caches
        case .logs: return .logs
        default: return .applications
        }
    }

    private func findingCategory(for relationship: ApplicationStorageRelationship) -> FindingCategory {
        switch relationship {
        case .cache: return .caches
        case .logs: return .logs
        default: return .applications
        }
    }

    private func orphanCandidateEntries(excluding installedIdentifiers: Set<String>) -> [StorageInventoryEntry] {
        orphanCandidates(excluding: installedIdentifiers).map { candidate in
            StorageInventoryEntry(
                key: "possible-orphan|\(candidate.relationship.rawValue)|\(candidate.url.path)",
                title: "Possible orphan: \(candidate.identifier)",
                path: candidate.url.path,
                category: category(for: candidate.relationship),
                byteSize: fileSystem.fileSize(at: candidate.url),
                origin: "Identifier-based application storage observation",
                explanation: "No installed application with this bundle identifier was found. Review this exact \(candidate.relationship.title.lowercased()) path before adding it to a cleanup plan.",
                risk: .reviewRequired,
                isActionable: true,
                modifiedAt: modificationDate(at: candidate.url)
            )
        }
    }

    private func orphanCandidates(excluding installedIdentifiers: Set<String>) -> [OrphanCandidate] {
        let library = home.appendingPathComponent("Library")
        let roots: [(URL, ApplicationStorageRelationship)] = [
            (library.appendingPathComponent("Application Support"), .supportData),
            (library.appendingPathComponent("Caches"), .cache),
            (library.appendingPathComponent("Logs"), .logs),
            (library.appendingPathComponent("Containers"), .container),
            (library.appendingPathComponent("Saved Application State"), .savedApplicationState),
            (library.appendingPathComponent("Preferences"), .preferences)
        ]
        return roots.flatMap { root, relationship in
            let children: [URL] = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            return children.compactMap { url -> OrphanCandidate? in
                let identifier = identifier(for: url, relationship: relationship)
                guard isBundleIdentifier(identifier), !installedIdentifiers.contains(identifier) else { return nil }
                return OrphanCandidate(
                    url: url.standardizedFileURL,
                    identifier: identifier,
                    relationship: relationship
                )
            }
        }
    }

    private struct OrphanCandidate {
        let url: URL
        let identifier: String
        let relationship: ApplicationStorageRelationship
    }

    private func identifier(for url: URL, relationship: ApplicationStorageRelationship) -> String {
        let name = url.lastPathComponent
        switch relationship {
        case .savedApplicationState:
            return name.hasSuffix(".savedState") ? String(name.dropLast(".savedState".count)) : name
        case .preferences:
            return name.hasSuffix(".plist") ? String(name.dropLast(".plist".count)) : name
        default:
            return name
        }
    }

    private func isBundleIdentifier(_ value: String) -> Bool {
        let components = value.split(separator: ".")
        return components.count >= 2 && components.allSatisfy { component in
            component.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }

    private func modificationDate(at url: URL) -> Date? {
        try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}
