import Foundation
import SecondWindCore

/// Captures known storage findings and compares each snapshot with its previous
/// local snapshot.
public struct StorageSnapshotService: Sendable {
    public let store: StorageSnapshotStore

    public init(store: StorageSnapshotStore = StorageSnapshotStore()) {
        self.store = store
    }

    public func capture(inventory: StorageInventory, totalBytes: Int64, availableBytes: Int64) -> StorageSnapshot {
        let entries = inventory.entries.map { entry in
            StorageSnapshotEntry(
                key: entry.key,
                title: entry.title,
                path: entry.path,
                category: entry.category.title,
                byteSize: entry.byteSize,
                origin: entry.origin,
                risk: entry.risk,
                explanation: entry.explanation,
                isActionable: entry.isActionable,
                countsTowardCategoryTotal: entry.countsTowardCategoryTotal,
                modifiedAt: entry.modifiedAt,
                applicationAssociations: entry.applicationAssociations,
                identity: entry.identity,
                ruleID: entry.ruleID,
                ruleVersion: entry.ruleVersion,
                provider: entry.provider,
                discoveryConfidence: entry.discoveryConfidence,
                supportedAction: entry.supportedAction
            )
        }.sorted { $0.byteSize > $1.byteSize }
        return StorageSnapshot(capturedAt: inventory.capturedAt, totalBytes: totalBytes, availableBytes: availableBytes, entries: entries)
    }

    public func capture(findings: [Finding], totalBytes: Int64, availableBytes: Int64, at date: Date = Date()) -> StorageSnapshot {
        let entries = findings.map { StorageInventoryEntry($0) }
        let inventory = StorageInventory(capturedAt: date, entries: entries)
        return capture(inventory: inventory, totalBytes: totalBytes, availableBytes: availableBytes)
    }

    public func report(for current: StorageSnapshot, history: [StorageSnapshot]) -> StorageSnapshotReport {
        let orderedHistory = history.sorted { $0.capturedAt < $1.capturedAt }
        guard let previous = orderedHistory.dropLast().last else {
            return StorageSnapshotReport(current: current, previous: nil, history: orderedHistory, changes: [])
        }

        let oldEntries = Dictionary(uniqueKeysWithValues: previous.entries.map { ($0.key, $0) })
        let minimumMeaningfulChange: Int64 = 1_024 * 1_024
        let currentKeys = Set(current.entries.map(\.key))
        let currentChanges = current.entries.compactMap { entry -> StorageChange? in
            guard let old = oldEntries[entry.key] else {
                return storageChange(
                    from: entry,
                    kind: .newlyObserved,
                    byteChange: entry.byteSize,
                    currentBytes: entry.byteSize
                )
            }
            let byteChange = entry.byteSize - old.byteSize
            guard abs(byteChange) >= minimumMeaningfulChange else { return nil }
            return storageChange(
                from: entry,
                kind: byteChange > 0 ? .grew : .shrank,
                byteChange: byteChange,
                currentBytes: entry.byteSize
            )
        }
        let noLongerObserved = previous.entries.compactMap { entry -> StorageChange? in
            guard !currentKeys.contains(entry.key), entry.byteSize >= minimumMeaningfulChange else { return nil }
            return storageChange(
                from: entry,
                kind: .noLongerObserved,
                byteChange: -entry.byteSize,
                currentBytes: 0,
                explanation: "This location was not observed by the latest scan. It may have moved, changed, or no longer exist.",
                isActionable: false
            )
        }
        let changes = (currentChanges + noLongerObserved).sorted { abs($0.byteChange) > abs($1.byteChange) }
        return StorageSnapshotReport(current: current, previous: previous, history: orderedHistory, changes: changes)
    }

    private func storageChange(
        from entry: StorageSnapshotEntry,
        kind: StorageChangeKind,
        byteChange: Int64,
        currentBytes: Int64,
        explanation: String? = nil,
        isActionable: Bool? = nil
    ) -> StorageChange {
        StorageChange(
            key: entry.key,
            title: entry.title,
            category: entry.category,
            kind: kind,
            byteChange: byteChange,
            currentBytes: currentBytes,
            risk: entry.risk,
            explanation: explanation ?? entry.explanation,
            isActionable: isActionable ?? entry.isActionable,
            origin: entry.origin,
            provider: entry.provider,
            ruleID: entry.ruleID,
            ruleVersion: entry.ruleVersion,
            applicationAssociations: entry.applicationAssociations
        )
    }
}
