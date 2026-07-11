import Foundation
import SecondWindCore

public struct PlanBuilder: Sendable {
    private let home: URL
    public init(home: URL) { self.home = home.standardizedFileURL }

    public func makePlan(findings: [Finding], selectedIDs: Set<UUID>, destination: PlanDestination) throws -> CleanupPlan {
        let selected = findings.filter { selectedIDs.contains($0.id) }
        guard !selected.isEmpty else { throw PlanError.noActions }
        var warnings: [String] = []
        let actions = try selected.map { finding -> PlanAction in
            guard finding.risk.isExecutable else { throw PlanError.protectedFinding(finding.path) }
            guard finding.supportedAction != .none else { throw PlanError.unsupportedAction(finding.path) }
            guard allowed(finding: finding, destination: destination) else { throw PlanError.destinationNotAllowed(finding.path) }
            if finding.confidence == .needsUserReview { warnings.append("Review required: \(finding.path)") }
            return PlanAction(findingID: finding.id, title: finding.title, sourcePath: finding.path, byteSize: finding.byteSize, risk: finding.risk, action: finding.supportedAction, confidence: finding.confidence)
        }
        return CleanupPlan(destination: destination, actions: actions, warnings: warnings)
    }

    public func validate(_ plan: CleanupPlan, requireConfirmation: Bool = true) throws {
        if requireConfirmation && plan.confirmedAt == nil { throw PlanError.planNotConfirmed }
        guard !plan.actions.isEmpty else { throw PlanError.noActions }
        for action in plan.actions {
            guard action.risk.isExecutable, action.action != .none else { throw PlanError.unsupportedAction(action.sourcePath) }
            let path = URL(fileURLWithPath: action.sourcePath).standardizedFileURL.path
            guard isUnderAllowedRoot(path, action: action.action, destination: plan.destination) else { throw PlanError.invalidPath(path) }
        }
    }

    private func allowed(finding: Finding, destination: PlanDestination) -> Bool {
        let path = URL(fileURLWithPath: finding.path).standardizedFileURL.path
        return isUnderAllowedRoot(path, action: finding.supportedAction, destination: destination)
    }
    private func isUnderAllowedRoot(_ path: String, action: SupportedAction, destination: PlanDestination) -> Bool {
        if destination == .systemTask { return false }
        let cleanupRoots = BuiltInRules.all
            .filter { $0.action == .cleanup && $0.risk.isExecutable }
            .map(\.relativePath)
        let userRoots = ["Downloads", "Desktop"]
        let applicationRoots = ["Applications", "Library/Application Support", "Library/Caches", "Library/Logs"]
        let absoluteApplicationRoots = ["/Applications"]
        let roots = cleanupRoots + userRoots + (action == .uninstall ? applicationRoots : [])
        if action == .uninstall && absoluteApplicationRoots.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) { return true }
        return roots.map { home.appendingPathComponent($0).path }.contains { path == $0 || path.hasPrefix($0 + "/") }
    }
}

public enum ExecutionResult: Codable, Sendable { case storedInRecovery(RecoveryItem), trashed(String) }

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
    private let recoveryRepository: any RecoveryRepository
    private let trashMover: any TrashMoving
    private let auditRecorder: any AuditRecording

    public init(planBuilder: PlanBuilder, recoveryRepository: any RecoveryRepository, trashMover: any TrashMoving, auditRecorder: any AuditRecording) {
        self.planBuilder = planBuilder
        self.recoveryRepository = recoveryRepository
        self.trashMover = trashMover
        self.auditRecorder = auditRecorder
    }
    public func execute(_ plan: CleanupPlan) throws -> [ExecutionResult] {
        try planBuilder.validate(plan)
        try auditRecorder.append(.init(kind: .executionStarted, planID: plan.id, ruleVersions: plan.actions.map { $0.title }, paths: plan.actions.map { $0.sourcePath }, bytes: plan.totalBytes, destination: plan.destination, result: "started"))
        var results: [ExecutionResult] = []
        var completedPaths: [String] = []

        for action in plan.actions {
            do {
                let url = URL(fileURLWithPath: action.sourcePath).standardizedFileURL
                let result: ExecutionResult
                switch plan.destination {
                case .recovery: result = .storedInRecovery(try recoveryRepository.storeInRecovery(url, planID: plan.id))
                case .finderTrash: try trashMover.moveToTrash(url); result = .trashed(action.sourcePath)
                case .systemTask: throw PlanError.destinationNotAllowed(action.sourcePath)
                }
                results.append(result)
                completedPaths.append(action.sourcePath)
            } catch {
                let executionError = PlanExecutionError.actionFailed(
                    completedPaths: completedPaths,
                    failedPath: action.sourcePath,
                    reason: error.localizedDescription
                )
                try? auditRecorder.append(.init(kind: .failure, planID: plan.id, ruleVersions: [], paths: completedPaths + [action.sourcePath], bytes: plan.actions.filter { completedPaths.contains($0.sourcePath) }.reduce(0) { $0 + $1.byteSize }, destination: plan.destination, result: executionError.localizedDescription))
                throw executionError
            }
        }

        try auditRecorder.append(.init(kind: .executionFinished, planID: plan.id, ruleVersions: [], paths: completedPaths, bytes: plan.totalBytes, destination: plan.destination, result: "success"))
        return results
    }
}
