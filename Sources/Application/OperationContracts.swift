import Foundation
import SecondWindCore

/// A named authority that coordinates one family of work.
public protocol Coordinator: Sendable {}

/// Admission and lifecycle authority for all user-initiated work. UI code
/// should never create a parallel operation timeline of its own.
public protocol OperationCoordinator: Coordinator {
    func start(kind: OperationKind) async throws -> OperationID
    func updateProgress(_ progress: OperationProgress, for operationID: OperationID) async
    func finish(_ operationID: OperationID) async
    func fail(_ operationID: OperationID, with failure: OperationFailure) async
    func cancel(_ operationID: OperationID) async
    func state(of operationID: OperationID) async -> OperationState?
    func isCancellationRequested(for operationID: OperationID) async -> Bool
}

/// Runs one provider-backed scan. Operation admission, cancellation, and
/// progress remain the responsibility of OperationCoordinator.
public protocol ScanRunner: Sendable {
    func scan(_ request: StorageScanRequest) -> AsyncStream<ScanRunEvent>
}

public enum ScanRunEvent: Sendable {
    case started(ScanRun)
    case progress(OperationProgress)
    case providerResult(ScanProviderResult)
    case completed(ScanRun, StorageInventory)
    case failed(ScanRun)
}

/// The common vocabulary for a named source of local facts. Specific provider
/// families add only the capability they actually need.
public protocol Provider: Sendable {
    var name: String { get }
}

/// A provider whose facts concern local storage. It deliberately says nothing
/// about whether those facts are part of the current inventory.
public protocol StorageProvider: Provider {}

/// A storage provider that contributes factual observations to the canonical
/// inventory. A missing optional path is an empty successful result, not an
/// error.
public protocol StorageInventoryProvider: StorageProvider {
    func observe(request: StorageScanRequest, cancellationRequested: @escaping @Sendable () async -> Bool) async throws -> ScanProviderResult
}

public protocol Reconciler: Sendable {}

public protocol StorageInventoryReconciler: Reconciler {
    /// Resolves only a set of observations that the capture identified as
    /// overlapping or otherwise contradictory.
    func reconcile(_ observations: [StorageObservation]) -> [StorageInventoryEntry]
}

/// The generic family for an underlying system derivation.
public protocol Capture: Sendable {}

public protocol StorageCapture: Capture {}

/// Collects storage facts into one canonical inventory. It is distinct from
/// reconciliation: ordinary, unambiguous observations become entries directly.
public protocol StorageInventoryCapture: StorageCapture {
    func capture(_ results: [ScanProviderResult], capturedAt: Date) -> StorageInventory
}

public protocol SystemLoadReading: Reader {
    func normalizedLoad() -> Double
}
