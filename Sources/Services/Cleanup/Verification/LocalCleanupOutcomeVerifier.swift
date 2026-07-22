import Foundation
import SecondWindCore
import SecondWindApplication

public struct LocalCleanupOutcomeVerifier: CleanupOutcomeVerifier {
    private let exists: @Sendable (URL) -> Bool
    private let availableBytes: @Sendable () -> Int64?

    public init(
        exists: @escaping @Sendable (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) },
        availableBytes: @escaping @Sendable () -> Int64? = {
            let home = FileManager.default.homeDirectoryForCurrentUser
            return try? home.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
        }
    ) {
        self.exists = exists
        self.availableBytes = availableBytes
    }

    public func verify(plan: CleanupPlan, results: [CleanupActionResult], availableBytesBefore: Int64?) async -> CleanupVerification {
        let verified = results.map { result -> CleanupActionResult in
            guard case .completedNotYetObservable = result.outcome else { return result }
            let source = URL(fileURLWithPath: result.action.sourcePath)
            return CleanupActionResult(action: result.action, outcome: exists(source) ? .completedNotYetObservable : .completedAndVerified, recoveryItem: result.recoveryItem)
        }
        let after = availableBytes()
        let difference = availableBytesBefore.flatMap { before in after.map { $0 - before } }
        return CleanupVerification(results: verified, observedFreeSpaceChange: difference)
    }
}
