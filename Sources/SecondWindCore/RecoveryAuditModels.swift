import Foundation

/// A recoverable file-system change. It is a domain value, not a persistence implementation.
public struct RecoveryItem: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let planID: UUID
    public let originalPath: String
    public let recoveryPath: String
    public let createdAt: Date
    public let byteSize: Int64

    public init(id: UUID, planID: UUID, originalPath: String, recoveryPath: String, createdAt: Date, byteSize: Int64) {
        self.id = id
        self.planID = planID
        self.originalPath = originalPath
        self.recoveryPath = recoveryPath
        self.createdAt = createdAt
        self.byteSize = byteSize
    }

    public var reviewAfter: Date { Calendar.current.date(byAdding: .day, value: 30, to: createdAt)! }
    public var needsReview: Bool { Date() >= reviewAfter }

    private enum CodingKeys: String, CodingKey {
        case id, planID, originalPath, createdAt, byteSize
        case recoveryPath = "quarantinedPath"
    }
}

public enum RecoveryError: LocalizedError {
    case missingPayload
    case invalidItem
    case restoreDestinationConflict

    public var errorDescription: String? {
        switch self {
        case .missingPayload: return "Stored recovery item is missing."
        case .invalidItem: return "Invalid recovery item."
        case .restoreDestinationConflict: return "A file already uses this item's restored name."
        }
    }
}

public enum AuditKind: String, Codable, Sendable {
    case scan, dryRun, executionStarted, executionFinished, manualTrash, restore, permanentDelete, failure, preference, maintenance
}

public struct AuditRecord: Codable, Identifiable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let kind: AuditKind
    public let planID: UUID?
    public let ruleVersions: [String]
    public let paths: [String]
    public let bytes: Int64
    public let destination: PlanDestination?
    public let result: String

    public init(id: UUID = UUID(), timestamp: Date = Date(), kind: AuditKind, planID: UUID? = nil, ruleVersions: [String], paths: [String], bytes: Int64, destination: PlanDestination? = nil, result: String) {
        self.id = id
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
