import Foundation
import SecondWindCore

/// A compact, UI-neutral summary of how known storage changed since the last
/// local snapshot. It only reorders and highlights StorageSnapshotReport data.
public struct StorageDeltaDashboard: Sendable {
    public let comparisonDate: Date?
    public let availableSpaceChange: Int64?
    public let largestCategoryGrowth: StorageCategoryChange?
    public let largestEntryGrowth: StorageChange?
    public let categoryChanges: [StorageCategoryChange]
    public let entryChanges: [StorageChange]

    public init(
        comparisonDate: Date?,
        availableSpaceChange: Int64?,
        largestCategoryGrowth: StorageCategoryChange?,
        largestEntryGrowth: StorageChange?,
        categoryChanges: [StorageCategoryChange],
        entryChanges: [StorageChange]
    ) {
        self.comparisonDate = comparisonDate
        self.availableSpaceChange = availableSpaceChange
        self.largestCategoryGrowth = largestCategoryGrowth
        self.largestEntryGrowth = largestEntryGrowth
        self.categoryChanges = categoryChanges
        self.entryChanges = entryChanges
    }

    public var hasComparison: Bool { comparisonDate != nil }
}

public struct StorageDeltaDashboardBuilder: Builder {
    public init() {}

    public func build(report: StorageSnapshotReport) -> StorageDeltaDashboard {
        let categoryChanges = report.categoryChanges
        let entryChanges = report.changes
        return StorageDeltaDashboard(
            comparisonDate: report.previous?.capturedAt,
            availableSpaceChange: report.availableSpaceChange,
            largestCategoryGrowth: categoryChanges.first(where: { $0.byteChange > 0 }),
            largestEntryGrowth: entryChanges.first(where: { $0.byteChange > 0 }),
            categoryChanges: categoryChanges,
            entryChanges: entryChanges
        )
    }
}

/// One local scan in chronological context. The values are derived solely from
/// stored snapshots, so the history has no independent persistence format.
public struct ScanHistoryEntry: Identifiable, Sendable {
    public let snapshot: StorageSnapshot
    public let observedBytes: Int64
    public let observedBytesChange: Int64?
    public let availableSpaceChange: Int64?

    public var id: UUID { snapshot.id }
}

public struct ScanHistoryBuilder: Builder {
    public init() {}

    public func build(snapshots: [StorageSnapshot]) -> [ScanHistoryEntry] {
        let orderedSnapshots = snapshots.sorted {
            $0.capturedAt > $1.capturedAt
        }

        return orderedSnapshots.enumerated().map { index, snapshot in
            let previous = orderedSnapshots.indices.contains(index + 1)
                ? orderedSnapshots[index + 1]
                : nil
            let currentObservedBytes = observedBytes(in: snapshot)

            return ScanHistoryEntry(
                snapshot: snapshot,
                observedBytes: currentObservedBytes,
                observedBytesChange: previous.map {
                    currentObservedBytes - observedBytes(in: $0)
                },
                availableSpaceChange: previous.map {
                    snapshot.availableBytes - $0.availableBytes
                }
            )
        }
    }

    private func observedBytes(in snapshot: StorageSnapshot) -> Int64 {
        snapshot.entries
            .filter(\.countsTowardCategoryTotal)
            .reduce(0) { $0 + $1.byteSize }
    }
}
