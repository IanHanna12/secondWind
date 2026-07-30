import Foundation
import SecondWindCore
import SecondWindApplication

/// Serializes mutations and holds scans until a mutation is finished. Durable
/// records intentionally use the same operation UUID as the UI lifecycle.
public actor LocalOperationCoordinator: OperationCoordinator {
    private struct Record {
        var kind: OperationKind
        var state: OperationState
        var progress: OperationProgress?
    }

    private var records: [OperationID: Record] = [:]
    private var activeMutations: Set<OperationID> = []
    private var inventoryWaiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func start(kind: OperationKind) async throws -> OperationID {
        if kind.isMutating {
            while !activeMutations.isEmpty {
                await withCheckedContinuation { inventoryWaiters.append($0) }
            }
        } else if kind.requiresStableInventory {
            while !activeMutations.isEmpty {
                await withCheckedContinuation { inventoryWaiters.append($0) }
            }
        }

        let id = OperationID()
        records[id] = Record(kind: kind, state: .running, progress: nil)
        if kind.isMutating { activeMutations.insert(id) }
        return id
    }

    public func updateProgress(_ progress: OperationProgress, for operationID: OperationID) {
        records[operationID]?.progress = progress
    }

    public func finish(_ operationID: OperationID) { finish(operationID, state: .completed) }

    public func fail(_ operationID: OperationID, with failure: OperationFailure) {
        _ = failure
        finish(operationID, state: failure == .cancelled ? .cancelled : .failed)
    }

    public func cancel(_ operationID: OperationID) {
        guard var record = records[operationID], record.state == .running || record.state == .waiting else { return }
        record.state = .cancelling
        records[operationID] = record
    }

    public func state(of operationID: OperationID) -> OperationState? { records[operationID]?.state }

    public func isCancellationRequested(for operationID: OperationID) -> Bool {
        records[operationID]?.state == .cancelling || records[operationID]?.state == .cancelled
    }

    private func finish(_ operationID: OperationID, state: OperationState) {
        guard var record = records[operationID] else { return }
        record.state = state
        records[operationID] = record
        guard activeMutations.remove(operationID) != nil, activeMutations.isEmpty else { return }
        let waiters = inventoryWaiters
        inventoryWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}
