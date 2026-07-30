import Foundation
import SecondWindApplication
import SecondWindCore
import SecondWindMacOS
import SecondWindPersistence

/// The application-facing entry point for Second Wind's local workflows.
///
/// UI code supplies intent and presents results. This type owns the concrete
/// service chain required to carry that intent through the shared operation
/// lifecycle.
public struct SecondWindWorkflows: Sendable {
    private let scanService: any StorageScanning
    private let planBuilder: PlanBuilder
    private let planExecutor: PlanExecutor
    private let cleanupVerifier: any CleanupOutcomeVerifier
    private let auditStore: any AuditStoring
    private let operationCoordinator: any OperationCoordinator

    public init(
        home: URL,
        store: LocalDataStore,
        operationCoordinator: any OperationCoordinator
    ) {
        let planBuilder = PlanBuilder(home: home)

        self.scanService = LocalStorageScanService(
            operationCoordinator: operationCoordinator,
            auditStore: store.audit,
            snapshotService: StorageSnapshotService(store: store.snapshots)
        )
        self.planBuilder = planBuilder
        self.planExecutor = PlanExecutor(
            planBuilder: planBuilder,
            recoveryStore: store.recovery,
            trashMover: FinderTrashMover(),
            auditStore: store.audit
        )
        self.cleanupVerifier = LocalCleanupOutcomeVerifier()
        self.auditStore = store.audit
        self.operationCoordinator = operationCoordinator
    }

    public func scan(_ request: StorageScanRequest) -> AsyncStream<StorageScanEvent> {
        scanService.scan(request)
    }

    public func cancel(_ operationID: OperationID) async {
        await operationCoordinator.cancel(operationID)
    }

    public func makeCleanupPlan(
        findings: [Finding],
        selectedIDs: Set<UUID>,
        destination: PlanDestination
    ) throws -> CleanupPlan {
        try planBuilder.makePlan(
            findings: findings,
            selectedIDs: selectedIDs,
            destination: destination
        )
    }

    public func recordCleanupReview(_ plan: CleanupPlan) throws {
        try auditStore.append(
            AuditRecord(
                kind: .dryRun,
                planID: plan.id,
                ruleVersions: plan.actions.map(\.ruleVersionDescription),
                paths: plan.actions.map(\.sourcePath),
                bytes: plan.totalBytes,
                result: "reviewed plan"
            )
        )
    }

    public func executeCleanup(
        _ plan: CleanupPlan,
        availableBytesBefore: Int64?
    ) async throws -> CleanupOutcome {
        let operationID = try await operationCoordinator.start(kind: .cleanup)

        do {
            let outcome = try await planExecutor.executeWithOutcome(
                plan.confirmed(),
                operationID: operationID,
                verifier: cleanupVerifier,
                availableBytesBefore: availableBytesBefore
            )
            await completeCleanupOperation(operationID, from: outcome)
            return outcome
        } catch {
            await operationCoordinator.fail(
                operationID,
                with: operationFailure(for: error)
            )
            throw error
        }
    }

    private func completeCleanupOperation(
        _ operationID: OperationID,
        from outcome: CleanupOutcome
    ) async {
        if let affectedPath = outcome.firstUnresolvedPath {
            await operationCoordinator.fail(
                operationID,
                with: .destinationUnavailable(path: affectedPath)
            )
        } else {
            await operationCoordinator.finish(operationID)
        }
    }

    private func operationFailure(for error: Error) -> OperationFailure {
        if let failure = error as? OperationFailure {
            return failure
        }
        if let planError = error as? PlanError {
            return .invalidPolicy(reason: planError.localizedDescription)
        }
        return .persistenceFailure(document: "local activity")
    }
}

private extension CleanupOutcome {
    var firstUnresolvedPath: String? {
        results.first { result in
            switch result.outcome {
            case .failed, .destinationConflict:
                return true
            case .completedAndVerified,
                 .completedNotYetObservable,
                 .skipped,
                 .sourceAbsent,
                 .rolledBack:
                return false
            }
        }?.action.sourcePath
    }
}
