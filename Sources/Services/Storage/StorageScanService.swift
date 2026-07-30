import Foundation
import SecondWindCore
import SecondWindApplication
import SecondWindMacOS
import SecondWindPersistence

/// UI-neutral updates from the one local storage scan workflow.
public enum StorageScanEvent: Sendable {
    case started(ScanRun)
    case progress(OperationProgress)
    case completed(StorageScanResult)
    case failed(ScanRun)
}

/// The completed read model from one local scan.
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

/// The app-facing scan contract. It adapts the canonical scan run into the
/// completed read model; it never starts a second discovery or inventory pass.
public protocol StorageScanning: Scanning {
    func scan(_ request: StorageScanRequest) -> AsyncStream<StorageScanEvent>
}

/// Builds the UI read model from the single provider-backed scan run.
public struct LocalStorageScanService: StorageScanning, Sendable {
    private let scanRunner: any ScanRunner
    private let snapshotService: StorageSnapshotService

    public init(
        scanRunner: any ScanRunner,
        snapshotService: StorageSnapshotService = StorageSnapshotService()
    ) {
        self.scanRunner = scanRunner
        self.snapshotService = snapshotService
    }

    public init(
        operationCoordinator: any OperationCoordinator = LocalOperationCoordinator(),
        auditStore: any AuditStoring,
        providers: [any StorageInventoryProvider] = [RuleFindingsStorageProvider(), PersonalFoldersStorageProvider(), ApplicationStorageProvider(), RecoveryStorageProvider()],
        inventoryCapture: any StorageInventoryCapture = LocalStorageInventoryCapture(),
        loadReader: any SystemLoadReading = FixedSystemLoadReader(),
        snapshotService: StorageSnapshotService = StorageSnapshotService()
    ) {
        self.init(
            scanRunner: LocalScanRunner(
                operationCoordinator: operationCoordinator,
                providers: providers,
                inventoryCapture: inventoryCapture,
                loadReader: loadReader,
                auditStore: auditStore
            ),
            snapshotService: snapshotService
        )
    }

    public func scan(_ request: StorageScanRequest) -> AsyncStream<StorageScanEvent> {
        AsyncStream { continuation in
            let worker = Task {
                var providerResults: [ScanProviderResult] = []
                for await event in scanRunner.scan(request) {
                    switch event {
                    case let .started(run):
                        continuation.yield(.started(run))
                    case let .progress(progress):
                        continuation.yield(.progress(progress))
                    case let .providerResult(result):
                        providerResults.append(result)
                    case let .completed(run, inventory):
                        let result = completedResult(
                            inventory: inventory,
                            providerResults: providerResults,
                            request: request
                        )
                        continuation.yield(.completed(result))
                        _ = run
                    case let .failed(run):
                        continuation.yield(.failed(run))
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in worker.cancel() }
        }
    }

    private func completedResult(
        inventory: StorageInventory,
        providerResults: [ScanProviderResult],
        request: StorageScanRequest
    ) -> StorageScanResult {
        let facts = StorageScanFacts(providerResults: providerResults)
        let associatedInventory = ApplicationAssociationResolver(home: request.home).resolve(
            inventory: inventory,
            applications: facts.applications
        )
        let snapshot = snapshotService.capture(
            inventory: associatedInventory,
            totalBytes: request.totalBytes,
            availableBytes: request.availableBytes
        )
        let history = (try? snapshotService.store.append(snapshot)) ?? snapshotService.store.snapshots()
        let snapshotReport = snapshotService.report(for: snapshot, history: history)
        return StorageScanResult(
            findings: facts.findings,
            applications: facts.applications,
            inventory: associatedInventory,
            snapshotReport: snapshotReport,
            summary: StorageScanSummary(findings: facts.findings, inventory: associatedInventory, startedAt: request.startedAt)
        )
    }
}

private struct StorageScanFacts: Sendable {
    let findings: [Finding]
    let applications: [InstalledApplication]

    init(providerResults: [ScanProviderResult]) {
        var findingsByID: [UUID: Finding] = [:]
        var applicationsByID: [String: InstalledApplication] = [:]

        for providerResult in providerResults {
            for finding in providerResult.findings {
                findingsByID[finding.id] = finding
            }
            for application in providerResult.applications {
                applicationsByID[application.id] = application
            }
        }

        findings = findingsByID.values.sorted { $0.path < $1.path }
        applications = applicationsByID.values.sorted {
            $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending
        }
    }
}
