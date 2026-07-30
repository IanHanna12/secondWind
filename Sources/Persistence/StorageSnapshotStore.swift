import Foundation
import SecondWindCore

/// Append-only local snapshot persistence. Snapshot data is kept in Application
/// Support and is never uploaded or used to load rules.
public final class StorageSnapshotStore: Store, @unchecked Sendable {
    private let snapshotFileURL: URL
    private let fileManager: FileManager

    public init(fileURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        // Keep the original on-disk location so existing local snapshots remain
        // visible after the feature rename from “Storage Story”.
        self.snapshotFileURL = fileURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SecondWind/StorageStory/snapshots.json")
    }

    public func snapshots() -> [StorageSnapshot] {
        guard let data = try? Data(contentsOf: snapshotFileURL), let snapshots = try? JSONDecoder.secondWind.decode([StorageSnapshot].self, from: data) else { return [] }
        return snapshots.sorted { $0.capturedAt < $1.capturedAt }
    }

    @discardableResult
    public func append(_ snapshot: StorageSnapshot) throws -> [StorageSnapshot] {
        var values = snapshots()
        if let last = values.last,
           snapshot.capturedAt.timeIntervalSince(last.capturedAt) < 30,
           last.totalBytes == snapshot.totalBytes,
           last.availableBytes == snapshot.availableBytes,
           last.entries == snapshot.entries {
            return values
        }
        values.append(snapshot)
        try fileManager.createDirectory(at: snapshotFileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder.secondWind.encode(values).write(to: snapshotFileURL, options: .atomic)
        return values
    }
}
