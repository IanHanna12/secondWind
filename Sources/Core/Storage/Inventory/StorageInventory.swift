import Foundation

/// A read-only account of storage locations Second Wind explicitly understands.
/// It is the current source of truth for cleanup, storage views, and snapshots.
public struct StorageInventory: Sendable {
    public let capturedAt: Date
    public let entries: [StorageInventoryEntry]

    public init(capturedAt: Date = Date(), entries: [StorageInventoryEntry]) {
        self.capturedAt = capturedAt
        self.entries = entries.sorted { $0.byteSize > $1.byteSize }
    }

}

public enum StorageCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case applications
    case developerStorage
    case downloads
    case documents
    case caches
    case logs
    case recovery
    case otherSystemData

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .applications: return "Applications"
        case .developerStorage: return "Developer Storage"
        case .downloads: return "Downloads"
        case .documents: return "Documents"
        case .caches: return "Caches"
        case .logs: return "Logs"
        case .recovery: return "Recovery Storage"
        case .otherSystemData: return "Other / System Data"
        }
    }

    public var explanation: String {
        switch self {
        case .applications: return "Known application bundles and their explicitly matched support data."
        case .developerStorage: return "Known developer tools, build artifacts, simulators, and package caches."
        case .downloads: return "Known downloaded files that meet an explicit rule."
        case .documents: return "Known user documents that meet an explicit rule."
        case .caches: return "Known application caches that can be recreated."
        case .logs: return "Known diagnostic logs created by applications."
        case .recovery: return "Items stored locally by Second Wind until you restore or delete them."
        case .otherSystemData: return "Known protected or system-related locations. This is not a claim about all macOS System Data."
        }
    }

    public static func forFindingCategory(_ category: FindingCategory?) -> StorageCategory {
        switch category {
        case .applications: return .applications
        case .developer, .containers, .packageManagers: return .developerStorage
        case .caches: return .caches
        case .logs: return .logs
        case .installers, .largeFiles: return .downloads
        case .browsers, .system, nil: return .otherSystemData
        }
    }

    public static func fromStoredTitle(_ title: String) -> StorageCategory {
        if let exact = StorageCategory.allCases.first(where: { $0.title == title }) { return exact }
        switch title {
        case "Developer", "Containers", "Package managers": return .developerStorage
        case "Browser", "System": return .otherSystemData
        default: return .otherSystemData
        }
    }
}

public struct StorageInventoryEntry: Hashable, Identifiable, Sendable {
    public let key: String
    public let title: String
    public let path: String?
    public let category: StorageCategory
    public let byteSize: Int64
    public let origin: String
    public let explanation: String
    public let risk: Risk
    public let isActionable: Bool
    public let countsTowardCategoryTotal: Bool
    public let modifiedAt: Date?
    public let applicationAssociations: [ApplicationAssociation]
    public let identity: StorageIdentity?
    public let ruleID: String?
    public let ruleVersion: Int?
    public let provider: String
    public let discoveryConfidence: StorageDiscoveryConfidence
    public let supportedAction: SupportedAction

    public var id: String { key }

    public init(_ finding: Finding, countsTowardCategoryTotal: Bool = true, modifiedAt: Date? = nil, applicationAssociations: [ApplicationAssociation] = []) {
        key = "finding|\(finding.ruleID)|\(finding.path)"
        title = finding.title
        path = finding.path
        category = .forFindingCategory(finding.category)
        byteSize = finding.byteSize
        origin = finding.origin
        explanation = finding.explanation
        risk = finding.risk
        isActionable = finding.risk.isExecutable && finding.supportedAction != .none
        self.countsTowardCategoryTotal = countsTowardCategoryTotal
        self.modifiedAt = modifiedAt
        self.applicationAssociations = applicationAssociations
        identity = .init(volumeID: "local", resolvedPath: finding.path)
        ruleID = finding.ruleID
        ruleVersion = finding.ruleVersion
        provider = finding.origin
        discoveryConfidence = finding.confidence == .exact ? .high : .medium
        supportedAction = finding.supportedAction
    }

    public init(_ recoveryItem: RecoveryItem) {
        key = "recovery|\(recoveryItem.id.uuidString)"
        title = "Recovery: \(URL(fileURLWithPath: recoveryItem.originalPath).lastPathComponent)"
        path = recoveryItem.originalPath
        category = .recovery
        byteSize = recoveryItem.byteSize
        origin = "Second Wind Recovery"
        explanation = "Stored locally by Second Wind. It remains recoverable until you choose to restore or delete it."
        risk = .protected
        isActionable = false
        countsTowardCategoryTotal = true
        modifiedAt = nil
        applicationAssociations = []
        identity = .init(volumeID: "local", resolvedPath: recoveryItem.recoveryPath)
        ruleID = recoveryItem.context.ruleID
        ruleVersion = recoveryItem.context.ruleVersion.flatMap(Int.init)
        provider = "Recovery provider"
        discoveryConfidence = .high
        supportedAction = .none
    }

    public init(key: String, title: String, path: String?, category: StorageCategory, byteSize: Int64, origin: String, explanation: String, risk: Risk, isActionable: Bool, countsTowardCategoryTotal: Bool = true, modifiedAt: Date? = nil, applicationAssociations: [ApplicationAssociation] = [], identity: StorageIdentity? = nil, ruleID: String? = nil, ruleVersion: Int? = nil, provider: String = "Unknown provider", discoveryConfidence: StorageDiscoveryConfidence = .medium, supportedAction: SupportedAction? = nil) {
        self.key = key
        self.title = title
        self.path = path
        self.category = category
        self.byteSize = byteSize
        self.origin = origin
        self.explanation = explanation
        self.risk = risk
        self.isActionable = isActionable
        self.countsTowardCategoryTotal = countsTowardCategoryTotal
        self.modifiedAt = modifiedAt
        self.applicationAssociations = applicationAssociations
        self.identity = identity ?? path.map { StorageIdentity(volumeID: "local", resolvedPath: $0) }
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.provider = provider
        self.discoveryConfidence = discoveryConfidence
        self.supportedAction = supportedAction ?? (isActionable ? .cleanup : .none)
    }

    public init(_ observation: StorageObservation, countsTowardCategoryTotal: Bool = true) {
        key = "storage|\(observation.identity.volumeID)|\(observation.identity.resolvedPath)"
        title = observation.title
        path = observation.identity.resolvedPath
        category = observation.category
        byteSize = observation.byteSize
        origin = observation.origin
        explanation = observation.explanation
        risk = observation.risk
        isActionable = observation.risk.isExecutable && observation.supportedAction != .none
        self.countsTowardCategoryTotal = countsTowardCategoryTotal
        modifiedAt = observation.modifiedAt
        applicationAssociations = observation.applicationAssociations
        identity = observation.identity
        ruleID = observation.ruleID
        ruleVersion = observation.ruleVersion
        provider = observation.provider
        discoveryConfidence = observation.discoveryConfidence
        supportedAction = observation.supportedAction
    }

    /// Returns this immutable entry with its resolved application metadata.
    public func withApplicationAssociations(_ associations: [ApplicationAssociation]) -> StorageInventoryEntry {
        StorageInventoryEntry(
            key: key,
            title: title,
            path: path,
            category: category,
            byteSize: byteSize,
            origin: origin,
            explanation: explanation,
            risk: risk,
            isActionable: isActionable,
            countsTowardCategoryTotal: countsTowardCategoryTotal,
            modifiedAt: modifiedAt,
            applicationAssociations: associations,
            identity: identity,
            ruleID: ruleID,
            ruleVersion: ruleVersion,
            provider: provider,
            discoveryConfidence: discoveryConfidence,
            supportedAction: supportedAction
        )
    }
}
