import Foundation
import SecondWindApplication
import SecondWindCore
import SecondWindPersistence

/// Builds an immutable observability value from the same persisted local facts
/// that the app already owns. It never starts a scan or writes a document.
public struct PersistedObservabilitySnapshotProvider: ObservabilitySnapshotProviding {
    private let dataStore: LocalDataStore
    private let includeApplicationMetrics: Bool

    public init(
        dataStore: LocalDataStore = LocalDataStore(),
        includeApplicationMetrics: Bool = false
    ) {
        self.dataStore = dataStore
        self.includeApplicationMetrics = includeApplicationMetrics
    }

    public func snapshot() async -> LocalObservabilitySnapshot? {
        let history = dataStore.snapshots.snapshots()
        guard let current = history.last else { return nil }

        let report = StorageSnapshotService(store: dataStore.snapshots).report(for: current, history: history)
        let recoveryItems = dataStore.recovery.allItems()
        let auditRecords = dataStore.audit.records()
        return makeSnapshot(
            current: current,
            report: report,
            recoveryItems: recoveryItems,
            recoveryAllocatedBytes: dataStore.recovery.allocatedByteSize(),
            auditRecords: auditRecords,
            generatedAt: Date()
        )
    }

    private func makeSnapshot(
        current: StorageSnapshot,
        report: StorageSnapshotReport,
        recoveryItems: [RecoveryItem],
        recoveryAllocatedBytes: Int64,
        auditRecords: [AuditRecord],
        generatedAt: Date
    ) -> LocalObservabilitySnapshot {
        let countedEntries = current.entries.filter(\.countsTowardCategoryTotal)
        let categories = categories(from: countedEntries, report: report)
        let inventory = InventorySummary(
            observedBytes: countedEntries.reduce(0) { $0 + $1.byteSize },
            entryCount: countedEntries.count,
            cleanupEligibleEntryCount: countedEntries.filter(\.isActionable).count,
            protectedEntryCount: countedEntries.filter { $0.risk == .protected }.count,
            categories: categories
        )
        let recovery = RecoverySummary(
            bytes: recoveryAllocatedBytes,
            itemCount: recoveryItems.count,
            oldestItemAgeSeconds: recoveryItems.map { generatedAt.timeIntervalSince($0.createdAt) }.max()
        )
        return LocalObservabilitySnapshot(
            generatedAt: generatedAt,
            inventory: inventory,
            scan: scanSummary(from: auditRecords, fallbackDate: current.capturedAt),
            recovery: recovery,
            cleanup: cleanupSummary(from: auditRecords),
            providers: .init(
                distinctProviderCount: Set(current.entries.map(\.provider)).count,
                observedEntryCount: current.entries.count
            ),
            delta: deltaSummary(from: report),
            applications: includeApplicationMetrics ? applicationSummary(from: current, report: report) : nil
        )
    }

    private func categories(from entries: [StorageSnapshotEntry], report: StorageSnapshotReport) -> [CategorySummary] {
        let currentTotals = Dictionary(grouping: entries, by: \.category).mapValues { values in
            (bytes: values.reduce(0) { $0 + $1.byteSize }, count: values.count)
        }
        let deltas = Dictionary(uniqueKeysWithValues: report.categoryChanges.map {
            ($0.category.title, $0.byteChange)
        })
        return currentTotals.map { category, total in
            CategorySummary(
                category: metricKey(category),
                observedBytes: total.bytes,
                entryCount: total.count,
                deltaBytes: deltas[category] ?? 0
            )
        }
        .sorted { $0.category < $1.category }
    }

    private func scanSummary(from records: [AuditRecord], fallbackDate: Date) -> ScanSummary {
        let scanRecords = records.filter { $0.kind == .scan }
        let completed = scanRecords.filter { $0.result.hasPrefix("completed:") }
        let failures = records.filter { $0.kind == .failure }
        return ScanSummary(
            lastCompletedAt: completed.map(\.timestamp).max() ?? fallbackDate,
            completedCount: completed.count,
            failedCount: failures.filter { !$0.result.localizedCaseInsensitiveContains("cancelled") }.count,
            cancelledCount: failures.filter { $0.result.localizedCaseInsensitiveContains("cancelled") }.count
        )
    }

    private func cleanupSummary(from records: [AuditRecord]) -> CleanupSummary {
        let finished = records.filter { $0.kind == .executionFinished || $0.kind == .manualTrash }
        return CleanupSummary(
            executionCount: finished.count,
            completedBytes: finished.reduce(0) { $0 + $1.bytes },
            trashBytes: finished.filter(isFinderTrash).reduce(0) { $0 + $1.bytes },
            recoveryBytes: finished.filter(isRecoveryDestination).reduce(0) { $0 + $1.bytes }
        )
    }

    private func isFinderTrash(_ record: AuditRecord) -> Bool {
        guard record.kind != .manualTrash else { return true }
        guard let destination = record.destination else { return false }
        if case .finderTrash = destination { return true }
        return false
    }

    private func isRecoveryDestination(_ record: AuditRecord) -> Bool {
        guard let destination = record.destination else { return false }
        if case .recovery = destination { return true }
        return false
    }

    private func deltaSummary(from report: StorageSnapshotReport) -> DeltaSummary {
        DeltaSummary(
            snapshotAvailable: report.current != nil,
            comparedSnapshotAvailable: report.previous != nil,
            availableStorageDeltaBytes: report.availableSpaceChange,
            largestCategoryChanges: report.categoryChanges.map {
                CategoryDelta(category: metricKey($0.category.title), byteChange: $0.byteChange, currentBytes: $0.currentBytes)
            }
        )
    }

    private func applicationSummary(from current: StorageSnapshot, report: StorageSnapshotReport) -> ApplicationSummary {
        let entries = current.entries.filter { !$0.applicationAssociations.isEmpty }
        return ApplicationSummary(
            associatedEntryCount: entries.count,
            observedBytes: entries.reduce(0) { $0 + $1.byteSize },
            deltaBytes: report.applicationChanges.reduce(0) { $0 + $1.byteChange }
        )
    }

    private func metricKey(_ text: String) -> String {
        text.lowercased()
            .replacingOccurrences(of: " / ", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .filter { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}

/// Keeps one immutable snapshot for the HTTP layer. A replacement is atomic
/// from the server's perspective; no request observes a partial refresh.
public actor LocalObservabilitySnapshotStore: ObservabilitySnapshotProviding, Store {
    private var current: LocalObservabilitySnapshot?

    public init(initial: LocalObservabilitySnapshot? = nil) {
        self.current = initial
    }

    public func replace(with snapshot: LocalObservabilitySnapshot?) {
        current = snapshot
    }

    public func snapshot() async -> LocalObservabilitySnapshot? {
        current
    }
}
