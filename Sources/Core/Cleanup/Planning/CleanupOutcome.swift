import Foundation

public enum CleanupActionOutcome: Codable, Equatable, Sendable {
    case completedAndVerified
    case completedNotYetObservable
    case skipped(reason: String)
    case failed(reason: String)
    case sourceAbsent
    case destinationConflict
    case rolledBack
}

public struct CleanupActionResult: Codable, Sendable {
    public let action: PlanAction
    public let outcome: CleanupActionOutcome
    public let recoveryItem: RecoveryItem?

    public init(action: PlanAction, outcome: CleanupActionOutcome, recoveryItem: RecoveryItem? = nil) {
        self.action = action
        self.outcome = outcome
        self.recoveryItem = recoveryItem
    }
}

public struct CleanupOutcome: Codable, Sendable {
    public let operationID: OperationID
    public let plannedBytes: Int64
    public let movedBytes: Int64
    public let results: [CleanupActionResult]
    public let observedFreeSpaceChange: Int64?

    public init(operationID: OperationID = OperationID(), plannedBytes: Int64, movedBytes: Int64, results: [CleanupActionResult], observedFreeSpaceChange: Int64? = nil) {
        self.operationID = operationID
        self.plannedBytes = plannedBytes
        self.movedBytes = movedBytes
        self.results = results
        self.observedFreeSpaceChange = observedFreeSpaceChange
    }
}
