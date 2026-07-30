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
        let byteSize = localFileSystem.logicalSize(at: source)
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

    /// Physical storage currently occupied by all Recovery payloads and
    /// manifests. Each manifest keeps logical content size separately as an
    /// integrity fact.
    public func allocatedByteSize() -> Int64 {
        LocalFileSystem(fileManager: fileManager).allocatedSize(at: root)
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
            let size = LocalFileSystem(fileManager: fileManager).logicalSize(at: payloadURL)
            guard size == item.byteSize else {
                return .init(item: item, status: .damaged(reason: "The stored payload size no longer matches its manifest."), canRestore: false)
            }
            return .init(item: item, status: .healthy, canRestore: true)
        } catch {
            return .init(item: item, status: .damaged(reason: "This item is outside its own Recovery folder."), canRestore: false)
        }
    }

    /// A conflict is intentionally discovered before the UI offers a restore
    /// action. The user, not a default, decides whether to preserve, replace,
    /// or choose a different destination.
    public func hasRestoreDestinationConflict(for item: RecoveryItem) -> Bool {
        fileManager.fileExists(atPath: URL(fileURLWithPath: item.originalPath).standardizedFileURL.path)
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

    /// Restores a set of Recovery items only after every item has passed a
    /// read-only preflight. Until every move succeeds, the manifests remain in
    /// place, which lets a later failure move completed items back into their
    /// original Recovery folders.
    public func restore(_ items: [RecoveryItem], choice: RestoreConflictChoice) -> RecoveryBatchOutcome {
        let uniqueItems = uniqueItems(from: items)
        guard !uniqueItems.isEmpty else { return .init(action: .restore, results: []) }

        // Replacement is intentionally a one-item operation. The UI presents
        // a second destructive confirmation before reaching this path; a
        // batch never gets permission to replace several current files.
        if case .replaceAfterDestructiveConfirmation = choice, uniqueItems.count == 1, let item = uniqueItems.first {
            do {
                let destination = try restore(item, choice: choice)
                return .init(action: .restore, results: [.init(itemID: item.id, outcome: .completed(destinationPath: destination.path))])
            } catch {
                return .init(action: .restore, results: [.init(itemID: item.id, outcome: .failed(reason: error.localizedDescription))])
            }
        }

        var prepared: [(item: RecoveryItem, payload: URL, destination: URL)] = []
        var preflightResults: [RecoveryItemActionResult] = []
        for item in uniqueItems {
            do {
                let payload = try validatedRecoveryPayloadURL(for: item)
                guard integrityReport(for: item).canRestore else {
                    preflightResults.append(.init(itemID: item.id, outcome: .skipped(reason: "The item did not pass its Recovery integrity check.")))
                    continue
                }
                let destination = try restoreDestination(for: item, choice: choice)
                prepared.append((item, payload, destination))
            } catch {
                preflightResults.append(.init(itemID: item.id, outcome: .skipped(reason: error.localizedDescription)))
            }
        }

        // A batch is all-or-nothing at admission. Nothing is moved until every
        // selected item is known to be restorable with the chosen policy.
        guard preflightResults.isEmpty else {
            let deferred = prepared.map {
                RecoveryItemActionResult(itemID: $0.item.id, outcome: .skipped(reason: "The batch did not start because another selected item was not ready."))
            }
            return .init(action: .restore, results: preflightResults + deferred)
        }

        var restored: [(item: RecoveryItem, payload: URL, destination: URL)] = []
        var failure: (item: RecoveryItem, error: Error)?
        for entry in prepared {
            do {
                try fileManager.createDirectory(at: entry.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: entry.payload, to: entry.destination)
                restored.append(entry)
            } catch {
                failure = (entry.item, error)
                break
            }
        }

        if let failure {
            return rollbackRestore(
                restored,
                failure: failure,
                unstarted: prepared.dropFirst(restored.count + 1).map(\.item)
            )
        }

        // The moves are now complete. Removing the empty per-item folders is
        // the commit step; a failure here still rolls every payload back.
        for entry in restored {
            do {
                try fileManager.removeItem(at: entry.payload.deletingLastPathComponent().deletingLastPathComponent())
            } catch {
                return rollbackRestore(restored, failure: (entry.item, error), unstarted: [])
            }
        }

        return .init(
            action: .restore,
            results: restored.map { .init(itemID: $0.item.id, outcome: .completed(destinationPath: $0.destination.path)) }
        )
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

    /// Permanently deleting a verified Recovery item is deliberately
    /// irreversible. Every item is preflighted first, so a known damaged or
    /// forged selection cannot cause an earlier item to be deleted.
    public func deletePermanently(_ items: [RecoveryItem]) -> RecoveryBatchOutcome {
        let uniqueItems = uniqueItems(from: items)
        guard !uniqueItems.isEmpty else { return .init(action: .permanentDelete, results: []) }

        var payloads: [(item: RecoveryItem, payload: URL)] = []
        var preflightResults: [RecoveryItemActionResult] = []
        for item in uniqueItems {
            do {
                let payload = try validatedRecoveryPayloadURL(for: item)
                guard fileManager.fileExists(atPath: payload.path) else { throw RecoveryError.missingPayload }
                payloads.append((item, payload))
            } catch {
                preflightResults.append(.init(itemID: item.id, outcome: .skipped(reason: error.localizedDescription)))
            }
        }
        guard preflightResults.isEmpty else {
            let deferred = payloads.map {
                RecoveryItemActionResult(itemID: $0.item.id, outcome: .skipped(reason: "The batch did not start because another selected item was not ready."))
            }
            return .init(action: .permanentDelete, results: preflightResults + deferred)
        }

        var results: [RecoveryItemActionResult] = []
        for (index, entry) in payloads.enumerated() {
            do {
                try fileManager.removeItem(at: entry.payload.deletingLastPathComponent().deletingLastPathComponent())
                results.append(.init(itemID: entry.item.id, outcome: .completed(destinationPath: nil)))
            } catch {
                results.append(.init(itemID: entry.item.id, outcome: .failed(reason: error.localizedDescription)))
                results.append(contentsOf: payloads.dropFirst(index + 1).map {
                    .init(itemID: $0.item.id, outcome: .skipped(reason: "Not deleted because an earlier permanent deletion failed."))
                })
                break
            }
        }
        return .init(action: .permanentDelete, results: results)
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

    private func restoreDestination(for item: RecoveryItem, choice: RestoreConflictChoice) throws -> URL {
        let originalDestination = URL(fileURLWithPath: item.originalPath).standardizedFileURL
        switch choice {
        case .cancel:
            throw RecoveryError.restoreDestinationConflict
        case .besideExisting:
            return fileManager.fileExists(atPath: originalDestination.path)
                ? try availableRestoreDestination(for: originalDestination, item: item)
                : originalDestination
        case let .anotherDestination(destination):
            let standardizedDestination = destination.standardizedFileURL
            guard !fileManager.fileExists(atPath: standardizedDestination.path) else {
                throw RecoveryError.restoreDestinationConflict
            }
            return standardizedDestination
        case .replaceAfterDestructiveConfirmation:
            // Batch replacement would destroy several unrelated current files
            // and cannot be rolled back. It stays a separate single-item
            // operation after the UI's destructive confirmation.
            throw RecoveryError.restoreDestinationConflict
        }
    }

    private func rollbackRestore(
        _ restored: [(item: RecoveryItem, payload: URL, destination: URL)],
        failure: (item: RecoveryItem, error: Error),
        unstarted: [RecoveryItem]
    ) -> RecoveryBatchOutcome {
        var results: [RecoveryItemActionResult] = []
        for entry in restored.reversed() {
            do {
                let recoveryItemFolder = entry.payload.deletingLastPathComponent().deletingLastPathComponent()
                let payloadFolder = entry.payload.deletingLastPathComponent()
                try fileManager.createDirectory(at: payloadFolder, withIntermediateDirectories: true)
                if !fileManager.fileExists(atPath: recoveryItemFolder.appendingPathComponent("manifest.json").path) {
                    try writeManifest(entry.item, in: recoveryItemFolder)
                }
                guard !fileManager.fileExists(atPath: entry.payload.path) else {
                    throw RecoveryError.restoreDestinationConflict
                }
                try fileManager.moveItem(at: entry.destination, to: entry.payload)
                results.append(.init(itemID: entry.item.id, outcome: .rolledBack))
            } catch {
                results.append(.init(itemID: entry.item.id, outcome: .unresolvedAfterRollback(reason: error.localizedDescription)))
            }
        }
        results.append(.init(itemID: failure.item.id, outcome: .failed(reason: failure.error.localizedDescription)))
        results.append(contentsOf: unstarted.map {
            .init(itemID: $0.id, outcome: .skipped(reason: "Not restored because an earlier item failed."))
        })
        return .init(action: .restore, results: results)
    }

    private func uniqueItems(from items: [RecoveryItem]) -> [RecoveryItem] {
        var processedItemIDs = Set<UUID>()
        return items.filter { processedItemIDs.insert($0.id).inserted }
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
