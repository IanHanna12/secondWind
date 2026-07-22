import Foundation
import SecondWindCore
import SecondWindApplication
import SecondWindMacOS
import SecondWindPersistence

/// Updates emitted during a local scan. UI code can render these on its actor
/// without knowing how scanning, inventory construction, or snapshots work.
public enum StorageScanEvent: Sendable {
    case progress(ScanProgress)
    case completed(StorageScanResult)
}

/// The completed result of one local scan.
public struct StorageScanResult: Sendable {
    public let findings: [Finding]
    public let applications: [InstalledApplication]
    public let inventory: StorageInventory
    public let snapshotReport: StorageSnapshotReport
    public let summary: StorageScanSummary

    public init(
        findings: [Finding],
        applications: [InstalledApplication],
        inventory: StorageInventory,
        snapshotReport: StorageSnapshotReport,
        summary: StorageScanSummary
    ) {
        self.findings = findings
        self.applications = applications
        self.inventory = inventory
        self.snapshotReport = snapshotReport
        self.summary = summary
    }
}

/// A compact, UI-neutral summary of a completed scan.
public struct StorageScanSummary: Sendable {
    public let completedAt: Date
    public let duration: TimeInterval
    public let findingCount: Int
    public let eligibleCount: Int
    public let reviewRequiredCount: Int
    public let protectedCount: Int
    public let observedBytes: Int64
    public let observedLocationCount: Int

    public init(findings: [Finding], inventory: StorageInventory, startedAt: Date, completedAt: Date = Date()) {
        self.completedAt = completedAt
        duration = completedAt.timeIntervalSince(startedAt)
        findingCount = findings.count
        eligibleCount = findings.filter { $0.risk.isExecutable && $0.supportedAction != .none }.count
        reviewRequiredCount = findings.filter { $0.risk == .reviewRequired }.count
        protectedCount = findings.filter { $0.risk == .protected || $0.supportedAction == .none }.count
        observedBytes = inventory.entries.filter(\.countsTowardCategoryTotal).reduce(0) { $0 + $1.byteSize }
        observedLocationCount = inventory.entries.count
    }
}

public protocol StorageScanning: Scanning {
    func events(for request: StorageScanRequest) -> AsyncStream<StorageScanEvent>
}

/// Coordinates a local scan outside the UI layer. The detached worker is owned
/// here because CleanupScanner is synchronous and can perform long filesystem
/// reads. It emits values only; it never touches UI state.
public struct LocalStorageScanService: StorageScanning, Sendable {
    private let auditStore: any AuditStoring
    private let snapshotService: StorageSnapshotService
    private let discoverApplications: @Sendable (URL) -> [InstalledApplication]
    private let observeInventory: @Sendable (URL, [Finding], [RecoveryItem], [InstalledApplication]) -> StorageInventory

    public init(
        auditStore: any AuditStoring,
        snapshotService: StorageSnapshotService = StorageSnapshotService(),
        discoverApplications: @escaping @Sendable (URL) -> [InstalledApplication] = { home in
            InstalledApplicationInventory(home: home).discoverApplications()
        },
        observeInventory: @escaping @Sendable (URL, [Finding], [RecoveryItem], [InstalledApplication]) -> StorageInventory = { home, findings, recoveryItems, applications in
            StorageInventoryObserver(home: home).observe(
                findings: findings,
                recoveryItems: recoveryItems,
                applications: applications
            )
        }
    ) {
        self.auditStore = auditStore
        self.snapshotService = snapshotService
        self.discoverApplications = discoverApplications
        self.observeInventory = observeInventory
    }

    public func events(for request: StorageScanRequest) -> AsyncStream<StorageScanEvent> {
        AsyncStream { continuation in
            let auditStore = auditStore
            let snapshotService = snapshotService
            let discoverApplications = discoverApplications
            let observeInventory = observeInventory
            let worker = Task.detached {
                continuation.yield(.progress(.init(
                    completedUnits: 0,
                    totalUnits: request.rules.count + 3,
                    currentTitle: "Preparing local scan"
                )))

                let fileSystem = LocalFileSystem()
                let outcome = CleanupScanner(home: request.home, fileSystem: fileSystem, rules: request.rules).scan { progress in
                    guard !Task.isCancelled else { return false }
                    continuation.yield(.progress(progress))
                    return true
                }
                guard case let .completed(findings) = outcome, !Task.isCancelled else {
                    continuation.finish()
                    return
                }

                continuation.yield(.progress(.init(
                    completedUnits: request.rules.count + 3,
                    totalUnits: request.rules.count + 3,
                    currentTitle: "Finishing scan"
                )))
                let applications = discoverApplications(request.home)
                let orphanFindings = ApplicationStorageObserver(home: request.home)
                    .orphanCleanupFindings(for: applications)
                let allFindings = findings + orphanFindings
                try? auditStore.append(.init(
                    operationID: request.operationID,
                    kind: .scan,
                    ruleVersions: Array(Set(allFindings.map { "\($0.ruleID) v\($0.ruleVersion)" })).sorted(),
                    paths: allFindings.map(\.path),
                    bytes: allFindings.reduce(0) { $0 + $1.byteSize },
                    result: "\(allFindings.count) findings"
                ))
                let inventory = observeInventory(request.home, allFindings, request.recoveryItems, applications)
                let snapshot = snapshotService.capture(
                    inventory: inventory,
                    totalBytes: request.totalBytes,
                    availableBytes: request.availableBytes
                )
                let history = (try? snapshotService.store.append(snapshot)) ?? snapshotService.store.snapshots()
                let report = snapshotService.report(for: snapshot, history: history)
                let result = StorageScanResult(
                    findings: allFindings,
                    applications: applications,
                    inventory: inventory,
                    snapshotReport: report,
                    summary: StorageScanSummary(findings: allFindings, inventory: inventory, startedAt: request.startedAt)
                )
                guard !Task.isCancelled else {
                    continuation.finish()
                    return
                }
                continuation.yield(.completed(result))
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in worker.cancel() }
        }
    }
}
