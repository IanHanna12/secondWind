import Foundation
import SecondWindCore

/// A schema-versioned, privacy-preserving snapshot served by Local
/// Observability. `generatedAt` remains the public JSON field; `capturedAt`
/// exposes the shared snapshot contract inside Swift.
public protocol ObservabilitySnapshot: Snapshot, Codable {
    static var currentSchemaVersion: Int { get }
    var schemaVersion: Int { get }
    var generatedAt: Date { get }
}

public extension ObservabilitySnapshot {
    var capturedAt: Date { generatedAt }
}

/// Starts and stops the optional local read-only endpoint.
public protocol LocalObservabilityServing: Service {
    func start() async throws
    func stop() async
}

/// Supplies the one immutable value served to every HTTP request.
public protocol ObservabilitySnapshotProviding: Sendable {
    func snapshot() async -> LocalObservabilitySnapshot?
}

public protocol PrometheusMetricsRendering: Renderer {
    func render(snapshot: LocalObservabilitySnapshot) -> String
}

public protocol ObservabilityJSONRendering: Renderer {
    func health(snapshot: LocalObservabilitySnapshot?) throws -> Data
    func summary(snapshot: LocalObservabilitySnapshot) throws -> Data
    func latestDelta(snapshot: LocalObservabilitySnapshot) throws -> Data
}

/// A privacy-preserving, immutable projection of persisted Second Wind facts.
/// It intentionally contains no paths, names, Recovery identifiers, or rules.
public struct LocalObservabilitySnapshot: ObservabilitySnapshot, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let generatedAt: Date
    public let inventory: InventorySummary
    public let scan: ScanSummary
    public let recovery: RecoverySummary
    public let cleanup: CleanupSummary
    public let providers: ProviderSummary
    public let delta: DeltaSummary
    public let applications: ApplicationSummary?

    public init(
        schemaVersion: Int = LocalObservabilitySnapshot.currentSchemaVersion,
        generatedAt: Date,
        inventory: InventorySummary,
        scan: ScanSummary,
        recovery: RecoverySummary,
        cleanup: CleanupSummary,
        providers: ProviderSummary,
        delta: DeltaSummary,
        applications: ApplicationSummary?
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.inventory = inventory
        self.scan = scan
        self.recovery = recovery
        self.cleanup = cleanup
        self.providers = providers
        self.delta = delta
        self.applications = applications
    }
}

public struct InventorySummary: Codable, Equatable, Summary {
    public let observedBytes: Int64
    public let entryCount: Int
    public let cleanupEligibleEntryCount: Int
    public let protectedEntryCount: Int
    public let categories: [CategorySummary]
}

public struct CategorySummary: Codable, Equatable, Identifiable, Summary {
    /// A fixed Second Wind category key, not a filesystem path or user value.
    public let category: String
    public let observedBytes: Int64
    public let entryCount: Int
    public let deltaBytes: Int64
    public var id: String { category }
}

public struct ScanSummary: Codable, Equatable, Summary {
    public let lastCompletedAt: Date?
    public let completedCount: Int
    public let failedCount: Int
    public let cancelledCount: Int
}

public struct RecoverySummary: Codable, Equatable, Summary {
    public let bytes: Int64
    public let itemCount: Int
    public let oldestItemAgeSeconds: TimeInterval?
}

public struct CleanupSummary: Codable, Equatable, Summary {
    public let executionCount: Int
    public let completedBytes: Int64
    public let trashBytes: Int64
    public let recoveryBytes: Int64
}

public struct ProviderSummary: Codable, Equatable, Summary {
    /// Counts observed provider identities without publishing their names.
    public let distinctProviderCount: Int
    public let observedEntryCount: Int
}

public struct ApplicationSummary: Codable, Equatable, Summary {
    /// Aggregate only: application identities are never exported as labels.
    public let associatedEntryCount: Int
    public let observedBytes: Int64
    public let deltaBytes: Int64
}

public struct DeltaSummary: Codable, Equatable, Summary {
    public let snapshotAvailable: Bool
    public let comparedSnapshotAvailable: Bool
    public let availableStorageDeltaBytes: Int64?
    public let largestCategoryChanges: [CategoryDelta]
}

public struct CategoryDelta: Codable, Sendable, Equatable, Identifiable {
    public let category: String
    public let byteChange: Int64
    public let currentBytes: Int64
    public var id: String { category }
}

public struct LocalObservabilityConfiguration: Sendable, Equatable {
    public let address: String
    public let port: UInt16
    public let includeApplicationMetrics: Bool
    public let refreshInterval: TimeInterval
    public let prometheusFilePath: String?

    public init(
        address: String = "127.0.0.1",
        port: UInt16 = 9467,
        includeApplicationMetrics: Bool = false,
        refreshInterval: TimeInterval = 15,
        prometheusFilePath: String? = nil
    ) throws {
        guard address == "127.0.0.1" else {
            throw LocalObservabilityError.nonLoopbackAddress(address)
        }
        guard port > 0 else { throw LocalObservabilityError.invalidPort }
        guard refreshInterval >= 1 else { throw LocalObservabilityError.invalidRefreshInterval }
        self.address = address
        self.port = port
        self.includeApplicationMetrics = includeApplicationMetrics
        self.refreshInterval = refreshInterval
        self.prometheusFilePath = prometheusFilePath
    }
}

public enum LocalObservabilityError: LocalizedError, Equatable, Sendable {
    case nonLoopbackAddress(String)
    case invalidPort
    case invalidRefreshInterval
    case invalidPrometheusFile
    case portUnavailable(UInt16)
    case serverNotRunning

    public var errorDescription: String? {
        switch self {
        case let .nonLoopbackAddress(address):
            return "Local Observability only accepts 127.0.0.1, not \(address)."
        case .invalidPort:
            return "Choose a valid local TCP port."
        case .invalidRefreshInterval:
            return "The local snapshot refresh interval must be at least one second."
        case .invalidPrometheusFile:
            return "Choose a writable Prometheus snapshot file."
        case let .portUnavailable(port):
            return "127.0.0.1:\(port) is already in use."
        case .serverNotRunning:
            return "The local observability server is not running."
        }
    }
}
