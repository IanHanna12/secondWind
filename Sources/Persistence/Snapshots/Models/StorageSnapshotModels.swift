import Foundation
import SecondWindCore

/// An immutable local copy of the current storage inventory. It intentionally
/// records only locations Second Wind explicitly understands, never a complete
/// index of a person's files.
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
    public let path: String?
    public let category: String
    public let byteSize: Int64
    public let origin: String?
    public let risk: Risk
    public let explanation: String
    public let isActionable: Bool
    public let countsTowardCategoryTotal: Bool
    public let modifiedAt: Date?

    public var id: String { key }

    public init(key: String, title: String, path: String? = nil, category: String, byteSize: Int64, origin: String? = nil, risk: Risk, explanation: String, isActionable: Bool, countsTowardCategoryTotal: Bool = true, modifiedAt: Date? = nil) {
        self.key = key
        self.title = title
        self.path = path
        self.category = category
        self.byteSize = byteSize
        self.origin = origin
        self.risk = risk
        self.explanation = explanation
        self.isActionable = isActionable
        self.countsTowardCategoryTotal = countsTowardCategoryTotal
        self.modifiedAt = modifiedAt
    }

    private enum CodingKeys: String, CodingKey { case key, title, path, category, byteSize, origin, risk, explanation, isActionable, countsTowardCategoryTotal, modifiedAt }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        title = try container.decode(String.self, forKey: .title)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        category = try container.decode(String.self, forKey: .category)
        byteSize = try container.decode(Int64.self, forKey: .byteSize)
        origin = try container.decodeIfPresent(String.self, forKey: .origin)
        risk = try container.decode(Risk.self, forKey: .risk)
        explanation = try container.decode(String.self, forKey: .explanation)
        isActionable = try container.decode(Bool.self, forKey: .isActionable)
        countsTowardCategoryTotal = try container.decodeIfPresent(Bool.self, forKey: .countsTowardCategoryTotal) ?? true
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
    }
}

public enum StorageChangeKind: String, Codable, Sendable {
    case grew
    case shrank
    case newlyObserved
    case noLongerObserved
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

    public var categorySummaries: [StorageCategorySummary] {
        guard let current else { return [] }
        let grouped = Dictionary(grouping: current.entries.filter(\.countsTowardCategoryTotal), by: { StorageCategory.fromStoredTitle($0.category) })
        return grouped.map { category, entries in
            StorageCategorySummary(category: category, byteSize: entries.reduce(0) { $0 + $1.byteSize }, entryCount: entries.count)
        }
        .sorted { $0.byteSize > $1.byteSize }
    }

    public var categoryChanges: [StorageCategoryChange] {
        guard let current, let previous else { return [] }
        let currentTotals = totalsByCategory(for: current.entries)
        let previousTotals = totalsByCategory(for: previous.entries)
        let categories = Set(currentTotals.keys).union(previousTotals.keys)
        let minimumMeaningfulChange: Int64 = 1_024 * 1_024
        return categories.compactMap { category in
            let currentBytes = currentTotals[category, default: 0]
            let byteChange = currentBytes - previousTotals[category, default: 0]
            guard abs(byteChange) >= minimumMeaningfulChange else { return nil }
            return StorageCategoryChange(category: category, byteChange: byteChange, currentBytes: currentBytes)
        }
        .sorted { abs($0.byteChange) > abs($1.byteChange) }
    }

    private func totalsByCategory(for entries: [StorageSnapshotEntry]) -> [StorageCategory: Int64] {
        Dictionary(grouping: entries.filter(\.countsTowardCategoryTotal), by: { StorageCategory.fromStoredTitle($0.category) })
            .mapValues { $0.reduce(0) { $0 + $1.byteSize } }
    }
}

public struct StorageCategorySummary: Identifiable, Sendable {
    public let category: StorageCategory
    public let byteSize: Int64
    public let entryCount: Int
    public var id: StorageCategory { category }
}

public struct StorageCategoryChange: Identifiable, Sendable {
    public let category: StorageCategory
    public let byteChange: Int64
    public let currentBytes: Int64
    public var id: StorageCategory { category }
}
