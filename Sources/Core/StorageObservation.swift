import Foundation

/// Immutable inputs supplied to one provider-backed storage scan.
public struct StorageScanRequest: Sendable {
    public let operationID: OperationID?
    public let home: URL
    public let rules: [BuiltInRule]
    public let recoveryItems: [RecoveryItem]
    public let totalBytes: Int64
    public let availableBytes: Int64
    public let startedAt: Date

    public init(
        operationID: OperationID? = nil,
        home: URL,
        rules: [BuiltInRule],
        recoveryItems: [RecoveryItem],
        totalBytes: Int64,
        availableBytes: Int64,
        startedAt: Date = Date()
    ) {
        self.operationID = operationID
        self.home = home.standardizedFileURL
        self.rules = rules
        self.recoveryItems = recoveryItems
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.startedAt = startedAt
    }
}

/// The canonical identity for a local storage observation. A volume identity
/// plus resolved path prevents aliases from being counted twice.
public struct StorageIdentity: Hashable, Codable, Sendable {
    public let volumeID: String
    public let resolvedPath: String

    public init(volumeID: String, resolvedPath: String) {
        self.volumeID = volumeID
        self.resolvedPath = URL(fileURLWithPath: resolvedPath).resolvingSymlinksInPath().standardizedFileURL.path
    }
}

/// How strongly Second Wind can explain the source of a storage observation.
/// It is descriptive only; cleanup policy remains governed by risk and action.
public enum StorageDiscoveryConfidence: String, Codable, CaseIterable, Sendable {
    case high
    case medium
    case low

    public var title: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

}

/// A provider's factual observation. It is not yet an inventory entry because
/// another provider may have observed the same path or one of its descendants.
public struct StorageObservation: Sendable {
    public let identity: StorageIdentity
    public let title: String
    public let category: StorageCategory
    public let byteSize: Int64
    public let origin: String
    public let explanation: String
    public let risk: Risk
    public let supportedAction: SupportedAction
    public let modifiedAt: Date?
    public let applicationAssociations: [ApplicationAssociation]
    public let ruleID: String?
    public let ruleVersion: Int?
    public let provider: String
    public let discoveryConfidence: StorageDiscoveryConfidence

    public init(
        identity: StorageIdentity,
        title: String,
        category: StorageCategory,
        byteSize: Int64,
        origin: String,
        explanation: String,
        risk: Risk,
        supportedAction: SupportedAction = .none,
        modifiedAt: Date? = nil,
        applicationAssociations: [ApplicationAssociation] = [],
        ruleID: String? = nil,
        ruleVersion: Int? = nil,
        provider: String = "Unknown provider",
        discoveryConfidence: StorageDiscoveryConfidence = .medium
    ) {
        self.identity = identity
        self.title = title
        self.category = category
        self.byteSize = max(0, byteSize)
        self.origin = origin
        self.explanation = explanation
        self.risk = risk
        self.supportedAction = supportedAction
        self.modifiedAt = modifiedAt
        self.applicationAssociations = applicationAssociations
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.provider = provider
        self.discoveryConfidence = discoveryConfidence
    }
}

public struct ScanRun: Identifiable, Codable, Sendable {
    public let id: OperationID
    public let startedAt: Date
    public let completedAt: Date?
    public let state: OperationState
    public let failure: OperationFailure?

    public init(id: OperationID = OperationID(), startedAt: Date = Date(), completedAt: Date? = nil, state: OperationState = .running, failure: OperationFailure? = nil) {
        self.id = id
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.state = state
        self.failure = failure
    }
}

public struct ScanProviderResult: Sendable {
    public let provider: String
    public let observations: [StorageObservation]
    /// Provider facts which are not representable by a storage observation,
    /// but belong to this same scan. They let the coordinator remain the one
    /// source of truth for scan work rather than triggering a second discovery.
    public let findings: [Finding]
    public let applications: [InstalledApplication]
    public let summary: String

    public init(
        provider: String,
        observations: [StorageObservation],
        findings: [Finding] = [],
        applications: [InstalledApplication] = [],
        summary: String? = nil
    ) {
        self.provider = provider
        self.observations = observations
        self.findings = findings
        self.applications = applications
        self.summary = summary ?? "\(observations.count) locations observed"
    }
}
