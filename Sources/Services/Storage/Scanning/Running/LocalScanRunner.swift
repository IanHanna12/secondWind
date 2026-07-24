import Foundation
import SecondWindCore
import SecondWindApplication
import SecondWindPersistence

public struct FixedSystemLoadReader: SystemLoadReading {
    public let load: Double
    public init(load: Double = 0) { self.load = load }
    public func normalizedLoad() -> Double { load }
}

/// Coordinates a coherent scan run. Provider results are useful progress but
/// never replace the last completed inventory until every provider succeeds.
public struct LocalScanRunner: ScanRunner {
    private let operationCoordinator: any OperationCoordinator
    private let providers: [any StorageInventoryProvider]
    private let inventoryCapture: any StorageInventoryCapture
    private let loadReader: any SystemLoadReading
    private let auditStore: (any AuditStoring)?

    public init(
        operationCoordinator: any OperationCoordinator = LocalOperationCoordinator(),
        providers: [any StorageInventoryProvider] = [RuleFindingsStorageProvider(), PersonalFoldersStorageProvider(), ApplicationStorageProvider(), RecoveryStorageProvider()],
        inventoryCapture: any StorageInventoryCapture = LocalStorageInventoryCapture(),
        loadReader: any SystemLoadReading = FixedSystemLoadReader(),
        auditStore: (any AuditStoring)? = nil
    ) {
        self.operationCoordinator = operationCoordinator
        self.providers = providers
        self.inventoryCapture = inventoryCapture
        self.loadReader = loadReader
        self.auditStore = auditStore
    }

    public func scan(_ request: StorageScanRequest) -> AsyncStream<ScanRunEvent> {
        AsyncStream { continuation in
            let worker = Task { await runScan(request, events: continuation) }
            continuation.onTermination = { @Sendable _ in worker.cancel() }
        }
    }

    public func providerLimit(for normalizedLoad: Double) -> Int {
        switch normalizedLoad {
        case ..<0.35: return 3
        case ..<0.70: return 2
        default: return 1
        }
    }

    private func runScan(
        _ request: StorageScanRequest,
        events: AsyncStream<ScanRunEvent>.Continuation
    ) async {
        guard let operation = await startScan(request) else {
            events.finish()
            return
        }

        events.yield(.started(operation.runningRun))
        do {
            try recordScanStart(operation)
            let results = try await collectProviderResults(for: operation, events: events)
            let inventory = inventoryCapture.capture(results, capturedAt: Date())
            try recordCompletedScan(operation, inventory: inventory)
            await operationCoordinator.finish(operation.id)
            events.yield(.completed(operation.completedRun, inventory))
        } catch {
            await publishFailure(for: operation, error: error, events: events)
        }
        events.finish()
    }

    private func startScan(_ request: StorageScanRequest) async -> ActiveScan? {
        do {
            let operationID = try await operationCoordinator.start(kind: .scan)
            return ActiveScan(id: operationID, request: request)
        } catch {
            return nil
        }
    }

    private func collectProviderResults(
        for operation: ActiveScan,
        events: AsyncStream<ScanRunEvent>.Continuation
    ) async throws -> [ScanProviderResult] {
        var collectedResults: [ScanProviderResult] = []
        var nextProviderIndex = 0

        while nextProviderIndex < providers.count {
            try await confirmScanCanContinue(operation.id)

            let concurrentProviderLimit = providerLimit(for: loadReader.normalizedLoad())
            let endIndex = min(providers.count, nextProviderIndex + concurrentProviderLimit)
            let providersToRun = Array(providers[nextProviderIndex..<endIndex])
            let batchResults = try await run(providersToRun, request: operation.request, operationID: operation.id)

            collectedResults.append(contentsOf: batchResults)
            publish(batchResults, to: events)

            nextProviderIndex = endIndex
            await publishProgress(
                completedProviders: nextProviderIndex,
                totalProviders: providers.count,
                operationID: operation.id,
                events: events
            )
        }

        return collectedResults
    }

    private func confirmScanCanContinue(_ operationID: OperationID) async throws {
        if await operationCoordinator.isCancellationRequested(for: operationID) || Task.isCancelled {
            throw OperationFailure.cancelled
        }
    }

    private func publish(_ results: [ScanProviderResult], to events: AsyncStream<ScanRunEvent>.Continuation) {
        for result in results {
            events.yield(.providerResult(result))
        }
    }

    private func publishProgress(
        completedProviders: Int,
        totalProviders: Int,
        operationID: OperationID,
        events: AsyncStream<ScanRunEvent>.Continuation
    ) async {
        let progress = OperationProgress(
            completedUnits: completedProviders,
            totalUnits: totalProviders,
            title: "Checked \(completedProviders) of \(totalProviders) sources"
        )
        await operationCoordinator.updateProgress(progress, for: operationID)
        events.yield(.progress(progress))
    }

    private func recordScanStart(_ operation: ActiveScan) throws {
        try appendAuditRecord(
            operationID: operation.id,
            request: operation.request,
            bytes: 0,
            result: "started"
        )
    }

    private func recordCompletedScan(_ operation: ActiveScan, inventory: StorageInventory) throws {
        let inventoryBytes = inventory.entries.reduce(0) { total, entry in total + entry.byteSize }
        try appendAuditRecord(
            operationID: operation.id,
            request: operation.request,
            bytes: inventoryBytes,
            result: "completed: \(inventory.entries.count) locations"
        )
    }

    private func appendAuditRecord(
        operationID: OperationID,
        request: StorageScanRequest,
        bytes: Int64,
        result: String
    ) throws {
        guard let auditStore else { return }
        do {
            try auditStore.append(.init(
                operationID: operationID,
                kind: .scan,
                ruleVersions: request.rules.map { rule in "\(rule.id) v\(rule.version)" },
                paths: [],
                bytes: bytes,
                result: result
            ))
        } catch {
            throw OperationFailure.persistenceFailure(document: "local activity")
        }
    }

    private func publishFailure(
        for operation: ActiveScan,
        error: Error,
        events: AsyncStream<ScanRunEvent>.Continuation
    ) async {
        let failure = operationFailure(from: error)
        await operationCoordinator.fail(operation.id, with: failure)
        try? auditStore?.append(.init(
            operationID: operation.id,
            kind: .failure,
            ruleVersions: [],
            paths: [],
            bytes: 0,
            result: failure.localizedDescription
        ))
        events.yield(.failed(operation.failedRun(for: failure)))
    }

    private func operationFailure(from error: Error) -> OperationFailure {
        if let failure = error as? OperationFailure { return failure }
        return .providerUnavailable(provider: error.localizedDescription)
    }

    private func run(_ providers: [any StorageInventoryProvider], request: StorageScanRequest, operationID: OperationID) async throws -> [ScanProviderResult] {
        try await withThrowingTaskGroup(of: ScanProviderResult.self) { group in
            for provider in providers {
                group.addTask {
                    try await provider.observe(request: request) { await operationCoordinator.isCancellationRequested(for: operationID) }
                }
            }
            var results: [ScanProviderResult] = []
            for try await result in group { results.append(result) }
            return results.sorted { $0.provider < $1.provider }
        }
    }
}

private struct ActiveScan: Sendable {
    let id: OperationID
    let request: StorageScanRequest

    var runningRun: ScanRun {
        ScanRun(id: id, startedAt: request.startedAt)
    }

    var completedRun: ScanRun {
        ScanRun(id: id, startedAt: request.startedAt, completedAt: Date(), state: .completed)
    }

    func failedRun(for failure: OperationFailure) -> ScanRun {
        let state: OperationState = failure == .cancelled ? .cancelled : .failed
        return ScanRun(id: id, startedAt: request.startedAt, completedAt: Date(), state: state, failure: failure)
    }
}
