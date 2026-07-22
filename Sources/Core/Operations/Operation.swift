import Foundation

/// A stable identifier shared by the UI lifecycle, audit records, and durable
/// work created by one user-initiated operation.
public struct OperationID: Codable, Hashable, Identifiable, Sendable {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public var id: UUID { rawValue }
}

public enum OperationKind: String, Codable, CaseIterable, Sendable {
    case scan
    case cleanup
    case restore
    case permanentDeletion
    case recoveryIntegrityCheck
    case policyChange
    case export
    case rulePreview

    public var isMutating: Bool {
        switch self {
        case .cleanup, .restore, .permanentDeletion, .policyChange: return true
        case .scan, .recoveryIntegrityCheck, .export, .rulePreview: return false
        }
    }

    /// Scanning needs a stable file-system view, even though it does not alter it.
    public var requiresStableInventory: Bool { self == .scan }

    public var isDurablyRecorded: Bool {
        switch self {
        case .scan, .cleanup, .restore, .permanentDeletion, .recoveryIntegrityCheck, .policyChange: return true
        case .export, .rulePreview: return false
        }
    }
}

public enum OperationState: String, Codable, Sendable {
    case waiting
    case running
    case cancelling
    case completed
    case cancelled
    case failed
}

/// Failures which can be shown safely without exposing a raw implementation
/// error or implying that a partially completed result is current.
public enum OperationFailure: Error, Codable, Equatable, Sendable, LocalizedError {
    case permissionDenied(path: String)
    case sourceChanged(path: String)
    case providerUnavailable(provider: String)
    case persistenceFailure(document: String)
    case invalidPolicy(reason: String)
    case recoveryConflict(path: String)
    case destinationUnavailable(path: String)
    case unsupportedFutureFormat(document: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case let .permissionDenied(path): return "Second Wind could not read \(path). Nothing was changed; allow access and scan again."
        case let .sourceChanged(path): return "\(path) changed while it was being checked. Nothing from this scan was saved; scan again."
        case let .providerUnavailable(provider): return "\(provider) is unavailable. The previous completed inventory remains visible."
        case let .persistenceFailure(document): return "Second Wind could not safely save \(document). No file operation was started."
        case let .invalidPolicy(reason): return "This rule policy is invalid: \(reason). Built-in rules remain available."
        case let .recoveryConflict(path): return "Recovery cannot safely restore to \(path) until you choose a destination."
        case let .destinationUnavailable(path): return "\(path) is unavailable. Nothing was changed."
        case let .unsupportedFutureFormat(document): return "\(document) was created by a newer version and was left untouched."
        case .cancelled: return "The operation was cancelled. The previous completed inventory remains visible."
        }
    }
}

public struct OperationProgress: Sendable, Equatable {
    public let completedUnits: Int
    public let totalUnits: Int
    public let title: String

    public init(completedUnits: Int, totalUnits: Int, title: String) {
        self.completedUnits = completedUnits
        self.totalUnits = max(1, totalUnits)
        self.title = title
    }

    public var fraction: Double { Double(completedUnits) / Double(totalUnits) }
}
