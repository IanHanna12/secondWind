import Darwin
import Foundation
import SecondWindCore

public struct InstalledApplicationInventory: @unchecked Sendable {
    private let fileManager: FileManager
    private let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager: FileManager = .default) {
        self.home = home
        self.fileManager = fileManager
    }

    public func applications() -> [InstalledApplication] {
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        return roots.flatMap { (try? fileManager.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }
            .filter { $0.pathExtension == "app" }
            .map { url in
                let bundle = Bundle(url: url)
                return InstalledApplication(
                    url: url,
                    bundleIdentifier: bundle?.bundleIdentifier,
                    displayName: (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? url.deletingPathExtension().lastPathComponent,
                    version: bundle?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
                    build: bundle?.object(forInfoDictionaryKey: "CFBundleVersion") as? String
                )
            }
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    public func discoverApplications() -> [InstalledApplication] {
        applications()
    }

    public func remnants(for app: InstalledApplication) -> [AppRemnant] {
        guard let identifier = app.bundleIdentifier else { return [] }
        let fileSystem = LocalFileSystem(fileManager: fileManager)
        let exact = [
            (kind: AppSupportPathKind.applicationSupport, path: "Library/Application Support/\(identifier)"),
            (kind: .cache, path: "Library/Caches/\(identifier)"),
            (kind: .log, path: "Library/Logs/\(identifier)")
        ]
        let exactItems = exact.compactMap { candidate -> AppRemnant? in
            let url = home.appendingPathComponent(candidate.path)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return AppRemnant(
                url: url,
                byteSize: fileSystem.fileSize(at: url),
                kind: candidate.kind,
                isExactKnownRemnant: true,
                explanation: "Exact \(candidate.kind.title.lowercased()) path for bundle identifier \(identifier)."
            )
        }
        let ambiguous = [home.appendingPathComponent("Library/Application Support/\(app.displayName)")].filter { fileManager.fileExists(atPath: $0.path) }.map { AppRemnant(url: $0, byteSize: fileSystem.fileSize(at: $0), kind: .nameMatch, isExactKnownRemnant: false, explanation: "Name-based match; it is not proven to belong to this app and stays protected.") }
        return exactItems + ambiguous
    }

    public func removalPreview(for app: InstalledApplication) -> ApplicationRemovalPreview {
        ApplicationRemovalPreview(application: app, applicationBytes: LocalFileSystem(fileManager: fileManager).fileSize(at: app.url), remnants: remnants(for: app), inspection: inspectRemoval(of: app))
    }

    public func uninstallFindings(for app: InstalledApplication) -> [Finding] {
        let preview = removalPreview(for: app)
        let appFinding = Finding(ruleID: "application-inventory", ruleVersion: BuiltInRules.version, title: "Application: \(app.displayName)", path: app.url.path, byteSize: preview.applicationBytes, category: .applications, origin: "Application inventory", explanation: "The selected application bundle.", risk: .reviewRequired, supportedAction: .uninstall, confidence: .exact)
        let remnantFindings = preview.remnants.map { remnant in
            Finding(ruleID: "application-remnant", ruleVersion: BuiltInRules.version, title: "\(remnant.kind.title) for \(app.displayName)", path: remnant.url.path, byteSize: remnant.byteSize, category: .applications, origin: "Application inventory", explanation: remnant.explanation, risk: remnant.isExactKnownRemnant ? .reviewRequired : .protected, supportedAction: remnant.isExactKnownRemnant ? .uninstall : .none, confidence: remnant.isExactKnownRemnant ? .exact : .needsUserReview)
        }
        return [appFinding] + remnantFindings
    }

    private func inspectRemoval(of app: InstalledApplication) -> ApplicationRemovalInspection {
        let attributes = (try? fileManager.attributesOfItem(atPath: app.url.path)) ?? [:]
        let ownerName = attributes[.ownerAccountName] as? String
        let ownerID = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
        let groupName = attributes[.groupOwnerAccountName] as? String
        let permissions = (attributes[.posixPermissions] as? NSNumber).map { String(format: "%04o", $0.intValue) } ?? "unknown"
        let owner = [ownerName ?? ownerID.map { "uid \($0)" } ?? "unknown", groupName].compactMap { $0 }.joined(separator: ":")
        let flags = fileFlags(at: app.url)
        let immutable = flags & (UInt32(UF_IMMUTABLE) | UInt32(SF_IMMUTABLE)) != 0
        let restricted = flags & UInt32(SF_RESTRICTED) != 0
        let protection = restricted ? "System protection restricts writes" : immutable ? "Immutable filesystem flag" : "No filesystem protection flag"
        let authorization: ApplicationMoveAuthorization = immutable || restricted ? .unavailable(reason: protection) : app.url.standardizedFileURL.deletingLastPathComponent() == URL(fileURLWithPath: "/Applications").standardizedFileURL && ownerID != UInt32(getuid()) ? .privilegedTrashMove : .standardUserMove
        return ApplicationRemovalInspection(path: app.url.path, owner: owner, permissions: permissions, hasExtendedACL: hasExtendedACL(at: app.url), protectionStatus: protection, moveAuthorization: authorization)
    }

    private func fileFlags(at url: URL) -> UInt32 { var information = stat(); guard lstat(url.path, &information) == 0 else { return 0 }; return UInt32(information.st_flags) }
    private func hasExtendedACL(at url: URL) -> Bool { let list = url.path.withCString { acl_get_file($0, ACL_TYPE_EXTENDED) }; guard let list else { return false }; defer { acl_free(UnsafeMutableRawPointer(list)) }; var entry: acl_entry_t?; return acl_get_entry(list, 0, &entry) == 0 }
}

extension InstalledApplicationInventory: ApplicationDiscovering {}
