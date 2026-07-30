import Foundation

/// Metadata read directly from an installed application bundle. Missing values
/// stay unavailable; Second Wind never estimates them.
public struct InstalledApplication: Identifiable, Hashable, Sendable {
    public let url: URL
    public let bundleIdentifier: String?
    public let displayName: String
    public let version: String?
    public let build: String?

    public var id: String { url.standardizedFileURL.path }

    public init(
        url: URL,
        bundleIdentifier: String?,
        displayName: String,
        version: String? = nil,
        build: String? = nil
    ) {
        self.url = url.standardizedFileURL
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.version = version
        self.build = build
    }
}

/// Discovers metadata from locally installed application bundles.
public protocol ApplicationDiscovering: Discoverer {
    func discoverApplications() -> [InstalledApplication]
}

/// Attaches explainable application relationships to known inventory entries.
/// Implementations must not change an entry's risk or cleanup eligibility.
public protocol ApplicationAssociationResolving: Resolver {
    func resolve(
        inventory: StorageInventory,
        applications: [InstalledApplication]
    ) -> StorageInventory
}

/// Builds the application-focused projection from the canonical inventory.
public protocol ApplicationInventoryBuilding: Builder {
    func build(
        storageInventory: StorageInventory,
        applications: [InstalledApplication]
    ) -> ApplicationInventory
}

public struct ApplicationInventoryBuilder: ApplicationInventoryBuilding {
    public init() {}

    public func build(
        storageInventory: StorageInventory,
        applications: [InstalledApplication]
    ) -> ApplicationInventory {
        ApplicationInventory(
            storageInventory: storageInventory,
            applications: applications
        )
    }
}

/// The relationship between one known storage entry and an application. It is
/// descriptive only; it does not make the entry eligible for cleanup.
public enum ApplicationStorageRelationship: String, Codable, CaseIterable, Identifiable, Sendable {
    case application
    case supportData
    case generatedData
    case cache
    case logs
    case preferences
    case savedApplicationState
    case container
    case groupContainer
    case extensionData
    case plugIn
    case developerData
    case userData
    case sharedResource
    case unknown

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .application: return "Application"
        case .supportData: return "Support Data"
        case .generatedData: return "Generated Data"
        case .cache: return "Cache"
        case .logs: return "Logs"
        case .preferences: return "Preferences"
        case .savedApplicationState: return "Saved Application State"
        case .container: return "Container"
        case .groupContainer: return "Group Container"
        case .extensionData: return "Extensions"
        case .plugIn: return "Plug-ins"
        case .developerData: return "Developer Data"
        case .userData: return "User Data"
        case .sharedResource: return "Shared Resource"
        case .unknown: return "Unknown"
        }
    }
}

/// Explains what evidence connected this storage entry to an application.
/// This is not a probability: `possibleOrphan`, for example, is an observed
/// identifier-shaped path without a currently installed matching app.
public enum ApplicationAssociationEvidence: String, Codable, Sendable {
    case exact
    case knownPath
    case possibleOrphan
    case uncertain

    public var title: String {
        switch self {
        case .exact: return "Exact identity"
        case .knownPath: return "Known application path"
        case .possibleOrphan: return "Possible orphan"
        case .uncertain: return "Uncertain association"
        }
    }
}

/// Stable metadata describing an application, independent of any associated storage.
public struct ApplicationIdentity: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let displayName: String
    public let bundleIdentifier: String?
    public let applicationPath: String?
    public let version: String?
    public let build: String?
    public let isInstalled: Bool

    public init(application: InstalledApplication) {
        id = application.bundleIdentifier ?? application.id
        displayName = application.displayName
        bundleIdentifier = application.bundleIdentifier
        applicationPath = application.url.path
        version = application.version
        build = application.build
        isInstalled = true
    }

    public init(orphanBundleIdentifier: String) {
        id = orphanBundleIdentifier
        displayName = orphanBundleIdentifier
        bundleIdentifier = orphanBundleIdentifier
        applicationPath = nil
        version = nil
        build = nil
        isInstalled = false
    }
}

public struct ApplicationAssociation: Codable, Hashable, Identifiable, Sendable {
    public let application: ApplicationIdentity
    public let relationship: ApplicationStorageRelationship
    public let reason: String
    public let evidence: ApplicationAssociationEvidence
    public let isShared: Bool

    public var id: String { "\(application.id)|\(relationship.rawValue)|\(reason)" }

    public init(
        application: ApplicationIdentity,
        relationship: ApplicationStorageRelationship,
        reason: String,
        evidence: ApplicationAssociationEvidence,
        isShared: Bool = false
    ) {
        self.application = application
        self.relationship = relationship
        self.reason = reason
        self.evidence = evidence
        self.isShared = isShared
    }
}

public struct ApplicationEntry: Hashable, Identifiable, Sendable {
    public let storage: StorageInventoryEntry
    public let association: ApplicationAssociation

    public var id: String { "\(association.application.id)|\(storage.id)" }

    public init(storage: StorageInventoryEntry, association: ApplicationAssociation) {
        self.storage = storage
        self.association = association
    }
}

/// A derived, read-only application-focused view of StorageInventory. It owns
/// no storage facts and does not alter cleanup eligibility.
public struct ApplicationProfile: Identifiable, Sendable {
    public let identity: ApplicationIdentity
    public let entries: [ApplicationEntry]

    public var id: String { identity.id }
    public var isPossibleOrphan: Bool { !identity.isInstalled && !entries.isEmpty }
    public var totalKnownBytes: Int64 { entries.reduce(0) { $0 + $1.storage.byteSize } }
    public var applicationBytes: Int64 { bytes(for: .application) }
    public var relatedBytes: Int64 { totalKnownBytes - applicationBytes }
    public var cleanupCandidateBytes: Int64 { entries.filter { $0.storage.isActionable }.reduce(0) { $0 + $1.storage.byteSize } }
    public var hasSharedStorage: Bool { entries.contains { $0.association.isShared } }
    public var relationships: [ApplicationStorageRelationship] {
        Array(Set(entries.map { $0.association.relationship })).sorted { $0.title < $1.title }
    }

    public func bytes(for relationship: ApplicationStorageRelationship) -> Int64 {
        entries
            .filter { $0.association.relationship == relationship }
            .reduce(0) { $0 + $1.storage.byteSize }
    }

    public func entries(for relationship: ApplicationStorageRelationship) -> [ApplicationEntry] {
        entries.filter { $0.association.relationship == relationship }.sorted { $0.storage.byteSize > $1.storage.byteSize }
    }
}

public struct ApplicationInventory: Sendable {
    public let profiles: [ApplicationProfile]

    public init(storageInventory: StorageInventory, applications: [InstalledApplication]) {
        var identities: [String: ApplicationIdentity] = [:]
        for app in applications {
            let identity = ApplicationIdentity(application: app)
            if identities[identity.id] == nil {
                identities[identity.id] = identity
            }
        }
        var entriesByApplication: [String: [ApplicationEntry]] = [:]

        for storageEntry in storageInventory.entries {
            for applicationAssociation in storageEntry.applicationAssociations {
                identities[applicationAssociation.application.id] = applicationAssociation.application
                entriesByApplication[applicationAssociation.application.id, default: []].append(
                    ApplicationEntry(storage: storageEntry, association: applicationAssociation)
                )
            }
        }

        profiles = identities.values.map { identity in
            ApplicationProfile(
                identity: identity,
                entries: (entriesByApplication[identity.id] ?? []).sorted { $0.storage.byteSize > $1.storage.byteSize }
            )
        }
        .filter { $0.identity.isInstalled || !$0.entries.isEmpty }
        .sorted { $0.totalKnownBytes > $1.totalKnownBytes }
    }

    public var installedProfiles: [ApplicationProfile] { profiles.filter { $0.identity.isInstalled } }
    public var possibleOrphans: [ApplicationProfile] { profiles.filter(\.isPossibleOrphan) }
}
