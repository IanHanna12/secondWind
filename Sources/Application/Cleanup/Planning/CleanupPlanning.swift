import Foundation
import SecondWindCore

public struct PlanBuilder: Builder {
    private let home: URL
    private let deletionPolicy: DeletionPolicy

    public init(home: URL, deletionPolicy: DeletionPolicy = DeletionPolicy()) {
        self.home = home.standardizedFileURL
        self.deletionPolicy = deletionPolicy
    }

    public func makePlan(findings: [Finding], selectedIDs: Set<UUID>, destination: PlanDestination) throws -> CleanupPlan {
        let selected = findings.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { throw PlanError.noActions }
        var warnings: [String] = []
        let actions = try selected.map { finding -> PlanAction in
            guard finding.risk.isExecutable else { throw PlanError.protectedFinding(finding.path) }
            guard finding.supportedAction != .none else { throw PlanError.unsupportedAction(finding.path) }
            guard deletionPolicy.permits(finding, destination: destination, home: home) else {
                throw PlanError.destinationNotAllowed(finding.path)
            }
            if finding.confidence == .needsUserReview {
                warnings.append("Review required: \(finding.path)")
            }
            return makeAction(from: finding)
        }
        return CleanupPlan(destination: destination, actions: actions, warnings: warnings)
    }

    public func validate(_ plan: CleanupPlan, requireConfirmation: Bool = true) throws {
        if requireConfirmation && plan.confirmedAt == nil {
            throw PlanError.planNotConfirmed
        }
        guard !plan.actions.isEmpty else { throw PlanError.noActions }
        for action in plan.actions {
            guard action.risk.isExecutable, action.action != .none else {
                throw PlanError.unsupportedAction(action.sourcePath)
            }
            guard deletionPolicy.permits(action, destination: plan.destination, home: home) else {
                throw PlanError.invalidPath(action.sourcePath)
            }
        }
    }

    private func makeAction(from finding: Finding) -> PlanAction {
        PlanAction(
            findingID: finding.id,
            ruleID: finding.ruleID,
            ruleVersion: finding.ruleVersion,
            title: finding.title,
            sourcePath: finding.path,
            byteSize: finding.byteSize,
            risk: finding.risk,
            action: finding.supportedAction,
            confidence: finding.confidence,
            category: finding.category
        )
    }

}

public enum ExecutionResult: Codable, Sendable {
    case storedInRecovery(RecoveryItem)
    case trashed(String)
}

/// An execution can stop after one or more actions have completed. The error
/// preserves that boundary so callers can direct people to Recovery or
/// Finder Trash instead of implying that the whole plan was rolled back.
public enum PlanExecutionError: LocalizedError, Equatable, Sendable {
    case actionFailed(completedPaths: [String], failedPath: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case let .actionFailed(completedPaths, failedPath, reason):
            if completedPaths.isEmpty {
                return "No items were changed. Failed to process \(failedPath): \(reason)"
            }
            return "\(completedPaths.count) item(s) were already moved before \(failedPath) failed: \(reason). Review Activity for their locations."
        }
    }
}

public struct PlanExecutor: Sendable {
    private let planBuilder: PlanBuilder
    private let recoveryStore: any RecoveryStoring
    private let trashMover: any TrashMoving
    private let auditStore: any AuditStoring
    private let sourceExists: @Sendable (URL) -> Bool

    public init(
        planBuilder: PlanBuilder,
        recoveryStore: any RecoveryStoring,
        trashMover: any TrashMoving,
        auditStore: any AuditStoring,
        sourceExists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) {
        self.planBuilder = planBuilder
        self.recoveryStore = recoveryStore
        self.trashMover = trashMover
        self.auditStore = auditStore
        self.sourceExists = sourceExists
    }

    public func execute(_ plan: CleanupPlan) async throws -> [ExecutionResult] {
        try planBuilder.validate(plan)
        let ruleVersions = Array(Set(plan.actions.map(\.ruleVersionDescription))).sorted()
        try auditStore.append(.init(kind: .executionStarted, planID: plan.id, ruleVersions: ruleVersions, paths: plan.actions.map(\.sourcePath), bytes: plan.totalBytes, destination: plan.destination, result: "started"))
        var results: [ExecutionResult] = []
        var completedPaths: [String] = []

        for action in plan.actions {
            do {
                let url = URL(fileURLWithPath: action.sourcePath).standardizedFileURL
                let result: ExecutionResult
                switch plan.destination {
                case .recovery:
                    result = .storedInRecovery(try recoveryStore.storeInRecovery(url, planID: plan.id))
                case .finderTrash:
                    try await trashMover.moveToTrash(url)
                    result = .trashed(action.sourcePath)
                case .systemTask:
                    throw PlanError.destinationNotAllowed(action.sourcePath)
                }
                results.append(result)
                completedPaths.append(action.sourcePath)
            } catch {
                let executionError = PlanExecutionError.actionFailed(
                    completedPaths: completedPaths,
                    failedPath: action.sourcePath,
                    reason: error.localizedDescription
                )
                try? auditStore.append(.init(
                    kind: .failure,
                    planID: plan.id,
                    ruleVersions: ruleVersions,
                    paths: completedPaths + [action.sourcePath],
                    bytes: completedBytes(for: completedPaths, in: plan.actions),
                    destination: plan.destination,
                    result: executionError.localizedDescription
                ))
                throw executionError
            }
        }

        try auditStore.append(.init(kind: .executionFinished, planID: plan.id, ruleVersions: ruleVersions, paths: completedPaths, bytes: plan.totalBytes, destination: plan.destination, result: "success"))
        return results
    }

    private func completedBytes(for paths: [String], in actions: [PlanAction]) -> Int64 {
        actions
            .filter { paths.contains($0.sourcePath) }
            .reduce(0) { $0 + $1.byteSize }
    }

    /// Executes every action with an explicit outcome. This is the UI-facing
    /// API for a reviewed cleanup: it never turns a partially completed plan
    /// into an ambiguous success message.
    public func executeWithOutcome(
        _ plan: CleanupPlan,
        operationID: OperationID? = nil,
        verifier: (any CleanupOutcomeVerifier)? = nil,
        availableBytesBefore: Int64? = nil
    ) async throws -> CleanupOutcome {
        try planBuilder.validate(plan)
        let sharedOperationID = operationID ?? OperationID(plan.id)
        let ruleVersions = Array(Set(plan.actions.map(\.ruleVersionDescription))).sorted()

        // This write is intentionally before the first move. If audit storage
        // is not writable, no cleanup begins.
        try auditStore.append(.init(operationID: sharedOperationID, kind: .executionStarted, planID: plan.id, ruleVersions: ruleVersions, paths: plan.actions.map(\.sourcePath), bytes: plan.totalBytes, destination: plan.destination, result: "started"))

        var results: [CleanupActionResult] = []
        var movedBytes: Int64 = 0
        for action in plan.actions {
            let source = URL(fileURLWithPath: action.sourcePath).standardizedFileURL
            guard sourceExists(source) else {
                results.append(.init(action: action, outcome: .sourceAbsent))
                continue
            }
            do {
                switch plan.destination {
                case .recovery:
                    let context = RecoveryContext(ruleID: action.ruleID, ruleVersion: String(action.ruleVersion), category: action.category.map { StorageCategory.forFindingCategory($0) })
                    let item: RecoveryItem
                    if let contextualStore = recoveryStore as? RecoveryContextStoring {
                        item = try contextualStore.storeInRecovery(source, planID: plan.id, context: context)
                    } else {
                        item = try recoveryStore.storeInRecovery(source, planID: plan.id)
                    }
                    movedBytes += action.byteSize
                    results.append(.init(action: action, outcome: .completedNotYetObservable, recoveryItem: item))
                case .finderTrash:
                    try await trashMover.moveToTrash(source)
                    movedBytes += action.byteSize
                    results.append(.init(action: action, outcome: .completedNotYetObservable))
                case .systemTask:
                    results.append(.init(action: action, outcome: .skipped(reason: PlanError.destinationNotAllowed(action.sourcePath).localizedDescription)))
                }
            } catch let error as RecoveryError where error == .restoreDestinationConflict {
                results.append(.init(action: action, outcome: .destinationConflict))
            } catch {
                results.append(.init(action: action, outcome: .failed(reason: error.localizedDescription)))
            }
        }
        let failed = results.filter { if case .failed = $0.outcome { return true }; return false }
        let resultText = failed.isEmpty ? "completed" : "completed with \(failed.count) failed action(s)"
        try auditStore.append(.init(operationID: sharedOperationID, kind: failed.isEmpty ? .executionFinished : .failure, planID: plan.id, ruleVersions: ruleVersions, paths: plan.actions.map(\.sourcePath), bytes: movedBytes, destination: plan.destination, result: resultText))
        guard let verifier else {
            return CleanupOutcome(operationID: sharedOperationID, plannedBytes: plan.totalBytes, movedBytes: movedBytes, results: results)
        }
        let verification = await verifier.verify(plan: plan, results: results, availableBytesBefore: availableBytesBefore)
        return CleanupOutcome(operationID: sharedOperationID, plannedBytes: plan.totalBytes, movedBytes: movedBytes, results: verification.results, observedFreeSpaceChange: verification.observedFreeSpaceChange)
    }
}
