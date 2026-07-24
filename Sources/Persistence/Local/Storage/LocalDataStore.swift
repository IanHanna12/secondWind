import Foundation
import SecondWindCore

/// The app's one local persistence entry point. Each nested store owns one
/// durable document or Recovery payload layout; callers do not construct or
/// coordinate those storage details independently.
public struct LocalDataStore: Store, @unchecked Sendable {
    public let audit: AuditStore
    public let recovery: RecoveryStore
    public let rulePolicy: RulePolicyStore
    public let snapshots: StorageSnapshotStore

    public init(
        audit: AuditStore = AuditStore(),
        recovery: RecoveryStore = RecoveryStore(),
        rulePolicy: RulePolicyStore = RulePolicyStore(),
        snapshots: StorageSnapshotStore = StorageSnapshotStore()
    ) {
        self.audit = audit
        self.recovery = recovery
        self.rulePolicy = rulePolicy
        self.snapshots = snapshots
    }
}
