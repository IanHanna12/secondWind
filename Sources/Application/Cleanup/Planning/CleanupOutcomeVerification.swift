import Foundation
import SecondWindCore

public struct CleanupVerification: Sendable {
    public let results: [CleanupActionResult]
    public let observedFreeSpaceChange: Int64?

    public init(results: [CleanupActionResult], observedFreeSpaceChange: Int64?) {
        self.results = results
        self.observedFreeSpaceChange = observedFreeSpaceChange
    }
}

/// A read-only postcondition check. It deliberately does not retry, move, or
/// delete anything after the cleanup handler has returned.
public protocol CleanupOutcomeVerifier: Verifier {
    func verify(plan: CleanupPlan, results: [CleanupActionResult], availableBytesBefore: Int64?) async -> CleanupVerification
}
