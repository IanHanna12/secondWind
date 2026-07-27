import Foundation
import SecondWindCore

/// A read-only explanation of one canonical inventory entry. It contains no
/// additional storage facts and is rebuilt from the current inventory entry.
public struct StorageInventoryExplanation: Identifiable, Sendable {
    public let entry: StorageInventoryEntry
    public let facts: [StorageExplanationFact]
    public let cleanupReasons: [String]
    public let protectionReasons: [String]
    public let relationshipReasons: [String]
    public let journey: [StorageJourneyStep]

    public var id: String { entry.id }
    public var canEnterCleanupPlan: Bool { entry.isActionable }
}

public struct StorageExplanationFact: Identifiable, Sendable {
    public let title: String
    public let value: String
    public let detail: String?

    public var id: String { title }

    public init(title: String, value: String, detail: String? = nil) {
        self.title = title
        self.value = value
        self.detail = detail
    }
}

/// One truthful stage in the path an entry has taken, or can take, through
/// Second Wind. It describes the existing flow; it never triggers work.
public struct StorageJourneyStep: Identifiable, Sendable {
    public let title: String
    public let detail: String

    public var id: String { title }

    public init(title: String, detail: String) {
        self.title = title
        self.detail = detail
    }
}
