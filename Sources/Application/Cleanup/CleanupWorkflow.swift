import Foundation
import SecondWindCore

/// The result of a read-only postcondition check. Verification never retries,
/// moves, or deletes an item after the cleanup action has returned.
public struct CleanupVerification: Sendable {
    public let results: [CleanupActionResult]
    public let observedFreeSpaceChange: Int64?

    public init(results: [CleanupActionResult], observedFreeSpaceChange: Int64?) {
        self.results = results
        self.observedFreeSpaceChange = observedFreeSpaceChange
    }
}

public protocol CleanupOutcomeVerifier: Verifier {
    func verify(
        plan: CleanupPlan,
        results: [CleanupActionResult],
        availableBytesBefore: Int64?
    ) async -> CleanupVerification
}

/// Builds and executes the one reviewed cleanup plan.
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

    /// Executes every action with an explicit outcome. This is the sole cleanup
    /// execution path: a partial result stays explicit instead of becoming an
    /// ambiguous thrown error.
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

/// A UI-neutral explanation of a cleanup finding. It adds no new cleanup
/// policy; it makes the existing finding policy ready to present and review.
public struct CleanupReviewCandidate: Identifiable, Sendable {
    public let finding: Finding
    public let reason: CleanupSuggestionReason
    public let regeneration: CleanupRegenerationStatus
    public let recovery: CleanupRecoveryAvailability

    public var id: UUID { finding.id }

    public init(
        finding: Finding,
        reason: CleanupSuggestionReason,
        regeneration: CleanupRegenerationStatus,
        recovery: CleanupRecoveryAvailability
    ) {
        self.finding = finding
        self.reason = reason
        self.regeneration = regeneration
        self.recovery = recovery
    }
}

public struct CleanupSuggestionReason: Sendable {
    public let origin: String
    public let explanation: String

    public init(origin: String, explanation: String) {
        self.origin = origin
        self.explanation = explanation
    }
}

public enum CleanupRegenerationStatus: Sendable, Equatable {
    case recreatedAutomatically
    case notGuaranteed
    case notApplicable

    public var detail: String {
        switch self {
        case .recreatedAutomatically:
            return "This known cache or generated data can be recreated when its app needs it."
        case .notGuaranteed:
            return "Review this item before cleanup; it may contain data that cannot be recreated automatically."
        case .notApplicable:
            return "Second Wind will not include this protected item in a cleanup plan."
        }
    }
}

public enum CleanupRecoveryAvailability: Sendable, Equatable {
    case available
    case unavailable

    public var detail: String {
        switch self {
        case .available:
            return "After review, you can keep this item in local Recovery and restore it later."
        case .unavailable:
            return "This item cannot be added to a cleanup plan."
        }
    }
}

/// Produces review-ready cleanup candidates from the current scan results.
/// It is deliberately pure so every screen sees the same explanation.
public struct CleanupReviewBuilder: Builder {
    public init() {}

    public func build(findings: [Finding]) -> [CleanupReviewCandidate] {
        findings.map(makeCandidate)
    }

    private func makeCandidate(for finding: Finding) -> CleanupReviewCandidate {
        CleanupReviewCandidate(
            finding: finding,
            reason: .init(origin: finding.origin, explanation: finding.explanation),
            regeneration: regenerationStatus(for: finding),
            recovery: recoveryAvailability(for: finding)
        )
    }

    private func regenerationStatus(for finding: Finding) -> CleanupRegenerationStatus {
        switch finding.risk {
        case .safe: return .recreatedAutomatically
        case .reviewRequired: return .notGuaranteed
        case .protected: return .notApplicable
        }
    }

    private func recoveryAvailability(for finding: Finding) -> CleanupRecoveryAvailability {
        finding.risk.isExecutable && finding.supportedAction != .none ? .available : .unavailable
    }
}
