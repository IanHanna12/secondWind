import Foundation
import SecondWindCore

/// A UI-neutral explanation of one cleanup finding. It adds no new cleanup
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

/// States why Second Wind surfaced a finding without hiding its original rule
/// source or explanation.
public struct CleanupSuggestionReason: Sendable {
    public let origin: String
    public let explanation: String

    public init(origin: String, explanation: String) {
        self.origin = origin
        self.explanation = explanation
    }
}

/// Describes whether Second Wind expects the item to be recreated after a
/// cleanup. Review-required data deliberately makes no such promise.
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
