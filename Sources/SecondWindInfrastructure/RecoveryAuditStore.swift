import Foundation
import SecondWindCore

public struct RecoveryStore: RecoveryRepository, @unchecked Sendable {
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
        let source = sourceURL.standardizedFileURL
        let itemID = UUID()
        let itemFolder = root.appendingPathComponent(itemID.uuidString, isDirectory: true)
        let payloadFolder = itemFolder.appendingPathComponent("payload", isDirectory: true)
        let payloadURL = payloadFolder.appendingPathComponent(source.lastPathComponent)

        let localFileSystem = LocalFileSystem(fileManager: fileManager)
        let byteSize = localFileSystem.fileSize(at: source)
        let item = RecoveryItem(
            id: itemID,
            planID: planID,
            originalPath: source.path,
            recoveryPath: payloadURL.path,
            createdAt: Date(),
            byteSize: byteSize
        )

        try fileManager.createDirectory(at: payloadFolder, withIntermediateDirectories: true)
        do {
            try fileManager.moveItem(at: source, to: payloadURL)
            try writeManifest(item, in: itemFolder)
            return item
        } catch {
            // A failed manifest must not silently strand a user's file. Try to
            // put a moved payload back before returning the original error.
            if fileManager.fileExists(atPath: payloadURL.path), !fileManager.fileExists(atPath: source.path) {
                try? fileManager.moveItem(at: payloadURL, to: source)
            }
            if !fileManager.fileExists(atPath: payloadURL.path) {
                try? fileManager.removeItem(at: itemFolder)
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

    /// Restores the payload to its original path. If another item now occupies
    /// that path, the restored item receives a numbered sibling name instead.
    @discardableResult
    public func restore(_ item: RecoveryItem) throws -> URL {
        let payloadURL = try validatedPayloadURL(for: item)
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            throw RecoveryError.missingPayload
        }

        var destination = URL(fileURLWithPath: item.originalPath)
        let destinationDirectory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: destination.path) {
            destination = try restoredDestination(for: destination, item: item)
        }

        try fileManager.moveItem(at: payloadURL, to: destination)
        try? fileManager.removeItem(at: payloadURL.deletingLastPathComponent().deletingLastPathComponent())
        return destination
    }

    /// Permanently removes an item that is already inside this store. Callers
    /// must obtain explicit user confirmation; this method never runs as part
    /// of cleanup execution or automated retention.
    public func deletePermanently(_ item: RecoveryItem) throws {
        let payloadURL = try validatedPayloadURL(for: item)
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            throw RecoveryError.missingPayload
        }
        try fileManager.removeItem(at: payloadURL.deletingLastPathComponent().deletingLastPathComponent())
    }

    /// A manifest describes a payload created by this store; it must never be
    /// allowed to turn `restore` into a move operation for an arbitrary path.
    private func validatedPayloadURL(for item: RecoveryItem) throws -> URL {
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

    private func writeManifest(_ item: RecoveryItem, in itemFolder: URL) throws {
        let manifestURL = itemFolder.appendingPathComponent("manifest.json")
        let data = try JSONEncoder.secondWind.encode(item)
        try data.write(to: manifestURL, options: .atomic)
    }

    private func readManifest(in itemFolder: URL) -> RecoveryItem? {
        let manifestURL = itemFolder.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL) else {
            return nil
        }
        return try? JSONDecoder.secondWind.decode(RecoveryItem.self, from: data)
    }

    /// Preserve the original name whenever possible. A collision gets a
    /// descriptive restore label rather than an arbitrary "2" or "3" suffix.
    private func restoredDestination(for originalURL: URL, item: RecoveryItem) throws -> URL {
        let directory = originalURL.deletingLastPathComponent()
        let baseName = originalURL.deletingPathExtension().lastPathComponent
        let fileExtension = originalURL.pathExtension
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        let restoreLabel = "Restored from Recovery — \(restorationTimestamp(for: item.createdAt))"
        let readableCandidate = directory.appendingPathComponent("\(baseName) (\(restoreLabel))\(suffix)")

        guard fileManager.fileExists(atPath: readableCandidate.path) else {
            return readableCandidate
        }

        // A stable item ID is only added if another restore from the
        // same second already occupies the descriptive filename.
        let identifiedCandidate = directory.appendingPathComponent(
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

public struct AuditStore: AuditRecording, Sendable {
    public let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SecondWind/audit.jsonl")
    }

    /// Appends compact JSON so each audit record occupies one line in the
    /// JSONL file. This deliberately does not use the pretty-printing encoder.
    public func append(_ record: AuditRecord) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)

        let handle: FileHandle
        if fileManager.fileExists(atPath: url.path) {
            handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
        } else {
            fileManager.createFile(atPath: url.path, contents: nil)
            handle = try FileHandle(forWritingTo: url)
        }

        defer { try? handle.close() }
        handle.write(data)
        handle.write(Data("\n".utf8))
    }

    public func records() -> [AuditRecord] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        return text
            .split(separator: "\n")
            .compactMap { try? JSONDecoder.secondWind.decode(AuditRecord.self, from: Data($0.utf8)) }
            .reversed()
    }

    public func exportJSON() throws -> Data {
        try JSONEncoder.secondWind.encode(records())
    }

    public func exportMarkdown() -> String {
        records()
            .map { record in
                "- \(record.timestamp.formatted()) — **\(record.kind.rawValue)**: \(record.result)\n" +
                    "  - Paths: \(record.paths.joined(separator: ", "))"
            }
            .joined(separator: "\n")
    }
}
