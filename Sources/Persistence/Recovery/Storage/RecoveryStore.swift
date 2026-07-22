import Foundation
import SecondWindCore
import SecondWindMacOS

public struct RecoveryStore: RecoveryStoring, RecoveryContextStoring, @unchecked Sendable {
    public let root: URL
    private let fileManager: FileManager

    public init(root: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.root = root ?? fileManager
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SecondWind/Quarantine", isDirectory: true)
    }

    /// Moves a file or directory into a per-item recovery folder and records
    /// the original location in a manifest beside its payload.
    public func storeInRecovery(_ sourceURL: URL, planID: UUID) throws -> RecoveryItem {
        try storeInRecovery(sourceURL, planID: planID, context: .init())
    }

    /// Stores the rule and application context observed at cleanup time so
    /// Recovery views never need to guess it from a later scan.
    public func storeInRecovery(_ sourceURL: URL, planID: UUID, context: RecoveryContext) throws -> RecoveryItem {
        let source = sourceURL.standardizedFileURL
        let recoveryItemID = UUID()
        let recoveryItemFolder = root.appendingPathComponent(recoveryItemID.uuidString, isDirectory: true)
        let payloadFolder = recoveryItemFolder.appendingPathComponent("payload", isDirectory: true)
        let payloadURL = payloadFolder.appendingPathComponent(source.lastPathComponent)

        let localFileSystem = LocalFileSystem(fileManager: fileManager)
        let byteSize = localFileSystem.fileSize(at: source)
        let recoveryItem = RecoveryItem(
            id: recoveryItemID,
            planID: planID,
            originalPath: source.path,
            recoveryPath: payloadURL.path,
            createdAt: Date(),
            byteSize: byteSize,
            context: context
        )

        try fileManager.createDirectory(at: payloadFolder, withIntermediateDirectories: true)
        do {
            try fileManager.moveItem(at: source, to: payloadURL)
            try writeManifest(recoveryItem, in: recoveryItemFolder)
            return recoveryItem
        } catch {
            // A failed manifest must not silently strand a user's file. Try to
            // put a moved payload back before returning the original error.
            if fileManager.fileExists(atPath: payloadURL.path), !fileManager.fileExists(atPath: source.path) {
                try? fileManager.moveItem(at: payloadURL, to: source)
            }
            if !fileManager.fileExists(atPath: payloadURL.path) {
                try? fileManager.removeItem(at: recoveryItemFolder)
            }
            throw error
        }
    }

    public func allItems() -> [RecoveryItem] {
        guard let itemFolders = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }

        return itemFolders
            .compactMap(readManifest(in:))
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func integrityReport(for item: RecoveryItem) -> RecoveryIntegrityReport {
        do {
            let payloadURL = try validatedRecoveryPayloadURL(for: item)
            guard fileManager.fileExists(atPath: payloadURL.path) else {
                return .init(item: item, status: .damaged(reason: "The stored payload is missing."), canRestore: false)
            }
            let manifestURL = payloadURL.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("manifest.json")
            guard let manifestData = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder.secondWind.decode(RecoveryItem.self, from: manifestData),
                  manifest.id == item.id,
                  manifest.recoveryPath == item.recoveryPath else {
                return .init(item: item, status: .damaged(reason: "The Recovery manifest is missing or does not match its payload."), canRestore: false)
            }
            let size = LocalFileSystem(fileManager: fileManager).fileSize(at: payloadURL)
            guard size == item.byteSize else {
                return .init(item: item, status: .damaged(reason: "The stored payload size no longer matches its manifest."), canRestore: false)
            }
            return .init(item: item, status: .healthy, canRestore: true)
        } catch {
            return .init(item: item, status: .damaged(reason: "This item is outside its own Recovery folder."), canRestore: false)
        }
    }

    /// Restores the payload to its original path. If another item now occupies
    /// that path, this chooses a descriptive available restore destination.
    @discardableResult
    public func restore(_ item: RecoveryItem) throws -> URL {
        try restore(item, choice: .besideExisting)
    }

    /// The UI must collect an explicit choice before this method is called.
    /// The legacy `restore(_:)` remains a compatibility wrapper for callers
    /// that historically chose a descriptive adjacent destination.
    @discardableResult
    public func restore(_ item: RecoveryItem, choice: RestoreConflictChoice) throws -> URL {
        // Validate containment before reporting integrity. A forged manifest
        // must remain an invalid item, never be softened into a missing file.
        let payloadURL = try validatedRecoveryPayloadURL(for: item)
        let integrity = integrityReport(for: item)
        guard integrity.canRestore else { throw RecoveryError.missingPayload }
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            throw RecoveryError.missingPayload
        }

        var restoreDestination = URL(fileURLWithPath: item.originalPath)
        if case let .anotherDestination(destination) = choice {
            restoreDestination = destination.standardizedFileURL
        }
        let restoreDirectory = restoreDestination.deletingLastPathComponent()
        try fileManager.createDirectory(at: restoreDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: restoreDestination.path) {
            switch choice {
            case .cancel: throw RecoveryError.restoreDestinationConflict
            case .besideExisting: restoreDestination = try availableRestoreDestination(for: restoreDestination, item: item)
            case .anotherDestination:
                throw RecoveryError.restoreDestinationConflict
            case .replaceAfterDestructiveConfirmation:
                try fileManager.removeItem(at: restoreDestination)
            }
        }

        try fileManager.moveItem(at: payloadURL, to: restoreDestination)
        try? fileManager.removeItem(at: payloadURL.deletingLastPathComponent().deletingLastPathComponent())
        return restoreDestination
    }

    /// Permanently removes an item that is already inside this store. Callers
    /// must obtain explicit user confirmation; this method never runs as part
    /// of cleanup execution or automated retention.
    public func deletePermanently(_ item: RecoveryItem) throws {
        let payloadURL = try validatedRecoveryPayloadURL(for: item)
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            throw RecoveryError.missingPayload
        }
        try fileManager.removeItem(at: payloadURL.deletingLastPathComponent().deletingLastPathComponent())
    }

    /// A manifest describes a payload created by this store; it must never be
    /// allowed to turn `restore` into a move operation for an arbitrary path.
    private func validatedRecoveryPayloadURL(for item: RecoveryItem) throws -> URL {
        guard item.originalPath.hasPrefix("/") else { throw RecoveryError.invalidItem }
        let originalURL = URL(fileURLWithPath: item.originalPath).standardizedFileURL
        guard !originalURL.lastPathComponent.isEmpty, originalURL.lastPathComponent != "/" else {
            throw RecoveryError.invalidItem
        }

        let expected = root
            .standardizedFileURL
            .appendingPathComponent(item.id.uuidString, isDirectory: true)
            .appendingPathComponent("payload", isDirectory: true)
            .appendingPathComponent(originalURL.lastPathComponent)
            .standardizedFileURL
        let supplied = URL(fileURLWithPath: item.recoveryPath).standardizedFileURL
        guard supplied == expected else { throw RecoveryError.invalidItem }
        return supplied
    }

    private func writeManifest(_ recoveryItem: RecoveryItem, in recoveryItemFolder: URL) throws {
        let manifestURL = recoveryItemFolder.appendingPathComponent("manifest.json")
        let data = try JSONEncoder.secondWind.encode(recoveryItem)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func readManifest(in recoveryItemFolder: URL) -> RecoveryItem? {
        let manifestURL = recoveryItemFolder.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }
        return try? JSONDecoder.secondWind.decode(RecoveryItem.self, from: data)
    }

    /// Preserve the original name whenever possible. A collision gets a
    /// descriptive restore label rather than an arbitrary "2" or "3" suffix.
    private func availableRestoreDestination(for originalDestination: URL, item: RecoveryItem) throws -> URL {
        let restoreDirectory = originalDestination.deletingLastPathComponent()
        let baseName = originalDestination.deletingPathExtension().lastPathComponent
        let fileExtension = originalDestination.pathExtension
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        let restoreLabel = "Restored from Recovery — \(restorationTimestamp(for: item.createdAt))"
        let readableCandidate = restoreDirectory.appendingPathComponent("\(baseName) (\(restoreLabel))\(suffix)")

        guard fileManager.fileExists(atPath: readableCandidate.path) else {
            return readableCandidate
        }

        // A stable item ID is only added if another restore from the
        // same second already occupies the descriptive filename.
        let identifiedCandidate = restoreDirectory.appendingPathComponent(
            "\(baseName) (\(restoreLabel) — \(item.id.uuidString))\(suffix)"
        )
        guard !fileManager.fileExists(atPath: identifiedCandidate.path) else {
            throw RecoveryError.restoreDestinationConflict
        }
        return identifiedCandidate
    }

    private func restorationTimestamp(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        return String(
            format: "%04d-%02d-%02d at %02d.%02d.%02d UTC",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )
    }
}
