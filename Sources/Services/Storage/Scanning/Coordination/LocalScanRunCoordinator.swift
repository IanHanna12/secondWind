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
public struct LocalScanRunCoordinator: ScanRunCoordinator {
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
            let worker = Task {
                let operationID: OperationID
                do { operationID = try await operationCoordinator.start(kind: .scan) }
                catch { return continuation.finish() }
                let running = ScanRun(id: operationID, startedAt: request.startedAt)
                continuation.yield(.started(running))
                do {
                    if let auditStore {
                        try auditStore.append(.init(operationID: operationID, kind: .scan, ruleVersions: request.rules.map { "\($0.id) v\($0.version)" }, paths: [], bytes: 0, result: "started"))
                    }
                    var results: [ScanProviderResult] = []
                    var providerIndex = 0
                    while providerIndex < providers.count {
                        if await operationCoordinator.isCancellationRequested(for: operationID) || Task.isCancelled { throw OperationFailure.cancelled }
                        let limit = providerLimit(for: loadReader.normalizedLoad())
                        let end = min(providers.count, providerIndex + limit)
                        let batch = Array(providers[providerIndex..<end])
                        let batchResults = try await run(batch, request: request, operationID: operationID)
                        for result in batchResults {
                            results.append(result)
                            continuation.yield(.providerResult(result))
                        }
                        providerIndex = end
                        let progress = OperationProgress(completedUnits: providerIndex, totalUnits: providers.count, title: "Checked \(providerIndex) of \(providers.count) sources")
                        await operationCoordinator.updateProgress(progress, for: operationID)
                        continuation.yield(.progress(progress))
                    }
                    let inventory = inventoryCapture.capture(results, capturedAt: Date())
                    await operationCoordinator.finish(operationID)
                    if let auditStore {
                        try auditStore.append(.init(operationID: operationID, kind: .scan, ruleVersions: request.rules.map { "\($0.id) v\($0.version)" }, paths: [], bytes: inventory.entries.reduce(0) { $0 + $1.byteSize }, result: "completed: \(inventory.entries.count) locations"))
                    }
                    continuation.yield(.completed(ScanRun(id: operationID, startedAt: request.startedAt, completedAt: Date(), state: .completed), inventory))
                } catch let failure as OperationFailure {
                    await operationCoordinator.fail(operationID, with: failure)
                    if let auditStore { try? auditStore.append(.init(operationID: operationID, kind: .failure, ruleVersions: [], paths: [], bytes: 0, result: failure.localizedDescription)) }
                    let state: OperationState = failure == .cancelled ? .cancelled : .failed
                    continuation.yield(.failed(ScanRun(id: operationID, startedAt: request.startedAt, completedAt: Date(), state: state, failure: failure)))
                } catch {
                    let failure = OperationFailure.providerUnavailable(provider: error.localizedDescription)
                    await operationCoordinator.fail(operationID, with: failure)
                    continuation.yield(.failed(ScanRun(id: operationID, startedAt: request.startedAt, completedAt: Date(), state: .failed, failure: failure)))
                }
                continuation.finish()
            }
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
