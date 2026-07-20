import Foundation

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

public struct StorageDeltaDashboardBuilder: Sendable {
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
