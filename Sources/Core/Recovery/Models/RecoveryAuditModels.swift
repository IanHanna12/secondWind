import Foundation

/// A recoverable file-system change. It is a domain value, not a persistence implementation.
public struct RecoveryItem: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let planID: UUID
    public let originalPath: String
    public let recoveryPath: String
    public let createdAt: Date
    public let byteSize: Int64
    public let context: RecoveryContext

    public init(id: UUID, planID: UUID, originalPath: String, recoveryPath: String, createdAt: Date, byteSize: Int64, context: RecoveryContext = .init()) {
        self.id = id
        self.planID = planID
        self.originalPath = originalPath
        self.recoveryPath = recoveryPath
        self.createdAt = createdAt
        self.byteSize = byteSize
        self.context = context
    }

    public var reviewAfter: Date { Calendar.current.date(byAdding: .day, value: 30, to: createdAt)! }
    public var needsReview: Bool { Date() >= reviewAfter }

    private enum CodingKeys: String, CodingKey {
        case id, planID, originalPath, createdAt, byteSize, context
        case recoveryPath = "quarantinedPath"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        planID = try container.decode(UUID.self, forKey: .planID)
        originalPath = try container.decode(String.self, forKey: .originalPath)
        recoveryPath = try container.decode(String.self, forKey: .recoveryPath)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        byteSize = try container.decode(Int64.self, forKey: .byteSize)
        context = try container.decodeIfPresent(RecoveryContext.self, forKey: .context) ?? .init()
    }
}

/// Context captured when a file enters Recovery, never inferred later from a
/// changed system or changed rule set.
public struct RecoveryContext: Codable, Hashable, Sendable {
    public let ruleID: String?
    public let ruleVersion: String?
    public let category: StorageCategory?
    public let applicationID: String?

    public init(ruleID: String? = nil, ruleVersion: String? = nil, category: StorageCategory? = nil, applicationID: String? = nil) {
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.category = category
        self.applicationID = applicationID
    }
}

public enum RecoveryIntegrityStatus: Codable, Equatable, Sendable {
    case healthy
    case damaged(reason: String)
    case unverified
}

public struct RecoveryIntegrityReport: Sendable {
    public let item: RecoveryItem
    public let status: RecoveryIntegrityStatus
    public let canRestore: Bool

    public init(item: RecoveryItem, status: RecoveryIntegrityStatus, canRestore: Bool) {
        self.item = item
        self.status = status
        self.canRestore = canRestore
    }
}

public enum RestoreConflictChoice: Sendable {
    case cancel
    case besideExisting
    case anotherDestination(URL)
    case replaceAfterDestructiveConfirmation
}

public enum RecoveryError: LocalizedError, Equatable {
    case missingPayload
    case invalidItem
    case restoreDestinationConflict

    public var errorDescription: String? {
        switch self {
        case .missingPayload: return "Stored recovery item is missing."
        case .invalidItem: return "Invalid recovery item."
        case .restoreDestinationConflict: return "A file already occupies this item's available restore destination."
        }
    }
}

public enum AuditKind: String, Codable, Sendable {
    case scan, dryRun, executionStarted, executionFinished, manualTrash, restore, permanentDelete, failure, preference, maintenance
}

public struct AuditRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let operationID: OperationID?
    public let timestamp: Date
    public let kind: AuditKind
    public let planID: UUID?
    public let ruleVersions: [String]
    public let paths: [String]
    public let bytes: Int64
    public let destination: PlanDestination?
    public let result: String

    public init(id: UUID = UUID(), operationID: OperationID? = nil, timestamp: Date = Date(), kind: AuditKind, planID: UUID? = nil, ruleVersions: [String], paths: [String], bytes: Int64, destination: PlanDestination? = nil, result: String) {
        self.id = id
        self.operationID = operationID
        self.timestamp = timestamp
        self.kind = kind
        self.planID = planID
        self.ruleVersions = ruleVersions
        self.paths = paths
        self.bytes = bytes
        self.destination = destination
        self.result = result
    }
}
