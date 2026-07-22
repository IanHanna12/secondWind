import Foundation

/// Input for one complete, local storage scan.
public struct StorageScanRequest: Sendable {
    public let operationID: OperationID?
    public let home: URL
    public let rules: [BuiltInRule]
    public let recoveryItems: [RecoveryItem]
    public let totalBytes: Int64
    public let availableBytes: Int64
    public let startedAt: Date

    public init(operationID: OperationID? = nil, home: URL, rules: [BuiltInRule], recoveryItems: [RecoveryItem], totalBytes: Int64, availableBytes: Int64, startedAt: Date = Date()) {
        self.operationID = operationID
        self.home = home.standardizedFileURL
        self.rules = rules
        self.recoveryItems = recoveryItems
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.startedAt = startedAt
    }
}
