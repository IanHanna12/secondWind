import Foundation
import SecondWindCore

/// Captures known storage findings and compares each snapshot with its previous
/// local snapshot.
public struct StorageSnapshotService: Sendable {
    public let store: StorageSnapshotStore

    public init(store: StorageSnapshotStore = StorageSnapshotStore()) {
        self.store = store
    }

    public func capture(findings: [Finding], totalBytes: Int64, availableBytes: Int64, at date: Date = Date()) -> StorageSnapshot {
        let entries = findings.map { finding in
            StorageSnapshotEntry(
                key: "\(finding.ruleID)|\(finding.path)",
                title: finding.title,
                category: finding.category?.title ?? "System",
                byteSize: finding.byteSize,
                risk: finding.risk,
                explanation: finding.explanation,
                isActionable: finding.risk.isExecutable && finding.supportedAction != .none
            )
        }.sorted { $0.byteSize > $1.byteSize }
        return StorageSnapshot(capturedAt: date, totalBytes: totalBytes, availableBytes: availableBytes, entries: entries)
    }

    public func report(for current: StorageSnapshot, history: [StorageSnapshot]) -> StorageSnapshotReport {
        let orderedHistory = history.sorted { $0.capturedAt < $1.capturedAt }
        guard let previous = orderedHistory.dropLast().last else {
            return StorageSnapshotReport(current: current, previous: nil, history: orderedHistory, changes: [])
        }

        let oldEntries = Dictionary(uniqueKeysWithValues: previous.entries.map { ($0.key, $0) })
        let minimumMeaningfulChange: Int64 = 1_024 * 1_024
        let changes = current.entries.compactMap { entry -> StorageChange? in
            guard let old = oldEntries[entry.key] else {
                return StorageChange(key: entry.key, title: entry.title, category: entry.category, kind: .newlyObserved, byteChange: entry.byteSize, currentBytes: entry.byteSize, risk: entry.risk, explanation: entry.explanation, isActionable: entry.isActionable)
            }
            let byteChange = entry.byteSize - old.byteSize
            guard abs(byteChange) >= minimumMeaningfulChange else { return nil }
            return StorageChange(key: entry.key, title: entry.title, category: entry.category, kind: byteChange > 0 ? .grew : .shrank, byteChange: byteChange, currentBytes: entry.byteSize, risk: entry.risk, explanation: entry.explanation, isActionable: entry.isActionable)
        }.sorted { abs($0.byteChange) > abs($1.byteChange) }
        return StorageSnapshotReport(current: current, previous: previous, history: orderedHistory, changes: changes)
    }
}
