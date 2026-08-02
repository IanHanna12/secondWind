import Foundation

/// Core values shared by cleanup planning and outcome reporting.
public enum FindingCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case caches, developer, browsers, logs, installers, largeFiles, applications, containers, packageManagers, system
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .caches: return "Caches"
        case .developer: return "Developer"
        case .browsers: return "Browser"
        case .logs: return "Logs"
        case .installers: return "Installers"
        case .largeFiles: return "Large files"
        case .applications: return "Applications"
        case .containers: return "Containers"
        case .packageManagers: return "Package managers"
        case .system: return "System"
        }
    }
}

public enum Risk: String, Codable, CaseIterable, Sendable {
    case safe = "Safe"
    case reviewRequired = "Review Required"
    case protected = "Protected"

    public var isExecutable: Bool { self != .protected }
}

public enum MatchConfidence: String, Codable, Sendable {
    case exact
    case needsUserReview
}

public enum SupportedAction: String, Codable, Sendable {
    case none
    case cleanup
    case uninstall
}
public enum PlanDestination: Codable, CaseIterable, Sendable {
    case recovery
    case finderTrash
    case systemTask

    public var label: String {
        switch self {
        case .recovery: return "Keep in Recovery"
        case .finderTrash: return "Move to Finder Trash"
        case .systemTask: return "Non-reversible system task"
        }
    }

    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "recovery", "quarantine": self = .recovery
        case "finderTrash": self = .finderTrash
        case "systemTask": self = .systemTask
        default:
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Unknown cleanup destination: \(value)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        let value: String
        switch self {
        case .recovery: value = "recovery"
        case .finderTrash: value = "finderTrash"
        case .systemTask: value = "systemTask"
        }
        try container.encode(value)
    }
}

public struct Finding: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let ruleID: String
    public let ruleVersion: Int
    public let title: String
    public let path: String
    public let byteSize: Int64
    public let category: FindingCategory?
    public let origin: String
    public let explanation: String
    public let risk: Risk
    public let supportedAction: SupportedAction
    public let confidence: MatchConfidence

    public init(id: UUID = UUID(), ruleID: String, ruleVersion: Int, title: String, path: String, byteSize: Int64, category: FindingCategory? = nil, origin: String, explanation: String, risk: Risk, supportedAction: SupportedAction, confidence: MatchConfidence) {
        self.id = id
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.title = title
        self.path = path
        self.byteSize = byteSize
        self.category = category
        self.origin = origin
        self.explanation = explanation
        self.risk = risk
        self.supportedAction = supportedAction
        self.confidence = confidence
    }
}

public struct CleanupPlan: Codable, Identifiable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let destination: PlanDestination
    public let actions: [PlanAction]
    public let warnings: [String]
    public var totalBytes: Int64 { actions.reduce(0) { $0 + $1.byteSize } }
    public var isDryRun: Bool { confirmedAt == nil }
    public private(set) var confirmedAt: Date?

    public init(id: UUID = UUID(), createdAt: Date = Date(), destination: PlanDestination, actions: [PlanAction], warnings: [String] = [], confirmedAt: Date? = nil) {
        self.id = id
        self.createdAt = createdAt
        self.destination = destination
        self.actions = actions
        self.warnings = warnings
        self.confirmedAt = confirmedAt
    }

    public func confirmed(at date: Date = Date()) -> CleanupPlan {
        CleanupPlan(id: id, createdAt: createdAt, destination: destination, actions: actions, warnings: warnings, confirmedAt: date)
    }
}

public struct PlanAction: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let findingID: UUID
    public let ruleID: String
    public let ruleVersion: Int
    public let title: String
    public let sourcePath: String
    public let byteSize: Int64
    public let risk: Risk
    public let action: SupportedAction
    public let confidence: MatchConfidence
    public let category: FindingCategory?

    public init(id: UUID = UUID(), findingID: UUID, ruleID: String, ruleVersion: Int, title: String, sourcePath: String, byteSize: Int64, risk: Risk, action: SupportedAction, confidence: MatchConfidence, category: FindingCategory? = nil) {
        self.id = id
        self.findingID = findingID
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.title = title
        self.sourcePath = sourcePath
        self.byteSize = byteSize
        self.risk = risk
        self.action = action
        self.confidence = confidence
        self.category = category
    }

    public var ruleVersionDescription: String { "\(ruleID) v\(ruleVersion)" }
}

public enum PlanError: LocalizedError, Equatable {
    case noActions
    case protectedFinding(String)
    case unsupportedAction(String)
    case destinationNotAllowed(String)
    case invalidPath(String)
    case planNotConfirmed
    public var errorDescription: String? {
        switch self {
        case .noActions: return "The plan has no executable actions."
        case .protectedFinding(let path): return "Protected finding cannot be executed: \(path)"
        case .unsupportedAction(let path): return "No supported action for: \(path)"
        case .destinationNotAllowed(let path): return "Destination is not allowed for: \(path)"
        case .invalidPath(let path): return "Path is outside this plan's allowlist: \(path)"
        case .planNotConfirmed: return "Review and explicitly confirm the plan before execution."
        }
    }
}

/// The explicit result of a cleanup operation. Every planned action remains
/// represented, including skipped, failed, and not-yet-observable actions.
public enum CleanupActionOutcome: Codable, Equatable, Outcome {
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

public struct CleanupOutcome: Codable, Outcome {
    public let operationID: OperationID
    public let plannedBytes: Int64
    public let movedBytes: Int64
    public let results: [CleanupActionResult]
    public let observedFreeSpaceChange: Int64?

    public init(
        operationID: OperationID = OperationID(),
        plannedBytes: Int64,
        movedBytes: Int64,
        results: [CleanupActionResult],
        observedFreeSpaceChange: Int64? = nil
    ) {
        self.operationID = operationID
        self.plannedBytes = plannedBytes
        self.movedBytes = movedBytes
        self.results = results
        self.observedFreeSpaceChange = observedFreeSpaceChange
    }
}

/// The application layer depends on these capabilities, never on concrete
/// disk or XPC services.
public protocol FileSystem: Sendable {
    func exists(_ url: URL) -> Bool
    func allocatedSize(at url: URL) -> Int64
    func directChildren(in root: URL) -> [URL]
    func regularFiles(in root: URL, maximumDepth: Int) -> [URL]
}

public protocol RecoveryStoring: Store {
    func storeInRecovery(_ sourceURL: URL, planID: UUID) throws -> RecoveryItem
    func allItems() -> [RecoveryItem]
    @discardableResult func restore(_ item: RecoveryItem) throws -> URL
    func deletePermanently(_ item: RecoveryItem) throws
}

/// A Recovery repository which persists the context known at cleanup time.
/// Kept separate so legacy repositories do not need a migration immediately.
public protocol RecoveryContextStoring: RecoveryStoring {
    func storeInRecovery(_ sourceURL: URL, planID: UUID, context: RecoveryContext) throws -> RecoveryItem
}

public protocol AuditStoring: Store {
    func append(_ record: AuditRecord) throws
}

public protocol TrashMoving: Mover {
    func moveToTrash(_ url: URL) async throws
}
