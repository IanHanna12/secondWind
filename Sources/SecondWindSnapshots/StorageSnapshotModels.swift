import Foundation
import SecondWindCore

/// A local, point-in-time account of storage that Second Wind understands.
/// It intentionally records only findings produced by bundled rules, never a
/// complete index of a person's files.
public struct StorageSnapshot: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let totalBytes: Int64
    public let availableBytes: Int64
    public let entries: [StorageSnapshotEntry]

    public init(id: UUID = UUID(), capturedAt: Date = Date(), totalBytes: Int64, availableBytes: Int64, entries: [StorageSnapshotEntry]) {
        self.id = id
        self.capturedAt = capturedAt
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.entries = entries
    }
}

public struct StorageSnapshotEntry: Codable, Hashable, Identifiable, Sendable {
    public let key: String
    public let title: String
    public let category: String
    public let byteSize: Int64
    public let risk: Risk
    public let explanation: String
    public let isActionable: Bool

    public var id: String { key }

    public init(key: String, title: String, category: String, byteSize: Int64, risk: Risk, explanation: String, isActionable: Bool) {
        self.key = key
        self.title = title
        self.category = category
        self.byteSize = byteSize
        self.risk = risk
        self.explanation = explanation
        self.isActionable = isActionable
    }
}

public enum StorageChangeKind: String, Codable, Sendable {
    case grew
    case shrank
    case newlyObserved
}

public struct StorageChange: Codable, Hashable, Identifiable, Sendable {
    public let key: String
    public let title: String
    public let category: String
    public let kind: StorageChangeKind
    public let byteChange: Int64
    public let currentBytes: Int64
    public let risk: Risk
    public let explanation: String
    public let isActionable: Bool

    public var id: String { key }

    public init(key: String, title: String, category: String, kind: StorageChangeKind, byteChange: Int64, currentBytes: Int64, risk: Risk, explanation: String, isActionable: Bool) {
        self.key = key
        self.title = title
        self.category = category
        self.kind = kind
        self.byteChange = byteChange
        self.currentBytes = currentBytes
        self.risk = risk
        self.explanation = explanation
        self.isActionable = isActionable
    }
}

public struct StorageSnapshotReport: Sendable {
    public let current: StorageSnapshot?
    public let previous: StorageSnapshot?
    public let history: [StorageSnapshot]
    public let changes: [StorageChange]

    public init(current: StorageSnapshot?, previous: StorageSnapshot?, history: [StorageSnapshot], changes: [StorageChange]) {
        self.current = current
        self.previous = previous
        self.history = history
        self.changes = changes
    }

    public static let empty = StorageSnapshotReport(current: nil, previous: nil, history: [], changes: [])
    public var isFirstSnapshot: Bool { current != nil && previous == nil }
    public var reclaimableBytes: Int64 {
        guard let current else { return 0 }

        let actionableEntries = current.entries.filter(\.isActionable)
        return actionableEntries.reduce(0) { totalBytes, entry in
            totalBytes + entry.byteSize
        }
    }
    public var availableSpaceChange: Int64? {
        guard let current, let previous else { return nil }
        return current.availableBytes - previous.availableBytes
    }
}
