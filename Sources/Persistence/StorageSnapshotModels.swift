import Foundation
import SecondWindCore

/// An immutable local copy of the current storage inventory. It intentionally
/// records only locations Second Wind explicitly understands, never a complete
/// index of a person's files.
public struct StorageSnapshot: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let capturedAt: Date
    public let totalBytes: Int64
    public let availableBytes: Int64
    public let entries: [StorageSnapshotEntry]

    public init(id: UUID = UUID(), capturedAt: Date = Date(), totalBytes: Int64, availableBytes: Int64, entries: [StorageSnapshotEntry]) {
        self.id = id
        self.capturedAt = capturedAt
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.entries = entries
    }
}

public struct StorageSnapshotEntry: Codable, Hashable, Identifiable, Sendable {
    public let key: String
    public let title: String
    public let path: String?
    public let category: String
    public let byteSize: Int64
    public let origin: String?
    public let risk: Risk
    public let explanation: String
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

    public init(key: String, title: String, path: String? = nil, category: String, byteSize: Int64, origin: String? = nil, risk: Risk, explanation: String, isActionable: Bool, countsTowardCategoryTotal: Bool = true, modifiedAt: Date? = nil, applicationAssociations: [ApplicationAssociation] = [], identity: StorageIdentity? = nil, ruleID: String? = nil, ruleVersion: Int? = nil, provider: String = "Unknown provider", discoveryConfidence: StorageDiscoveryConfidence = .medium, supportedAction: SupportedAction? = nil) {
        self.key = key
        self.title = title
        self.path = path
        self.category = category
        self.byteSize = byteSize
        self.origin = origin
        self.risk = risk
        self.explanation = explanation
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

    private enum CodingKeys: String, CodingKey { case key, title, path, category, byteSize, origin, risk, explanation, isActionable, countsTowardCategoryTotal, modifiedAt, applicationAssociations, identity, ruleID, ruleVersion, provider, discoveryConfidence, supportedAction }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        key = try container.decode(String.self, forKey: .key)
        title = try container.decode(String.self, forKey: .title)
        path = try container.decodeIfPresent(String.self, forKey: .path)
        category = try container.decode(String.self, forKey: .category)
        byteSize = try container.decode(Int64.self, forKey: .byteSize)
        origin = try container.decodeIfPresent(String.self, forKey: .origin)
        risk = try container.decode(Risk.self, forKey: .risk)
        explanation = try container.decode(String.self, forKey: .explanation)
        isActionable = try container.decode(Bool.self, forKey: .isActionable)
        countsTowardCategoryTotal = try container.decodeIfPresent(Bool.self, forKey: .countsTowardCategoryTotal) ?? true
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt)
        applicationAssociations = try container.decodeIfPresent([ApplicationAssociation].self, forKey: .applicationAssociations) ?? []
        identity = try container.decodeIfPresent(StorageIdentity.self, forKey: .identity)
            ?? path.map { StorageIdentity(volumeID: "local", resolvedPath: $0) }
        ruleID = try container.decodeIfPresent(String.self, forKey: .ruleID)
        ruleVersion = try container.decodeIfPresent(Int.self, forKey: .ruleVersion)
        provider = try container.decodeIfPresent(String.self, forKey: .provider) ?? "Unknown provider"
        discoveryConfidence = try container.decodeIfPresent(StorageDiscoveryConfidence.self, forKey: .discoveryConfidence) ?? .medium
        supportedAction = try container.decodeIfPresent(SupportedAction.self, forKey: .supportedAction) ?? (isActionable ? .cleanup : .none)
    }
}

public enum StorageChangeKind: String, Codable, Sendable {
    case grew
    case shrank
    case newlyObserved
    case noLongerObserved
}

public struct StorageChange: Codable, Hashable, Identifiable, Sendable {
    public let key: String
    public let title: String
    public let category: String
    public let kind: StorageChangeKind
    public let byteChange: Int64
    public let currentBytes: Int64
    public let risk: Risk
    public let explanation: String
    public let isActionable: Bool
    public let origin: String?
    public let provider: String
    public let ruleID: String?
    public let ruleVersion: Int?
    public let applicationAssociations: [ApplicationAssociation]

    public var id: String { key }

    public init(key: String, title: String, category: String, kind: StorageChangeKind, byteChange: Int64, currentBytes: Int64, risk: Risk, explanation: String, isActionable: Bool, origin: String? = nil, provider: String = "Unknown provider", ruleID: String? = nil, ruleVersion: Int? = nil, applicationAssociations: [ApplicationAssociation] = []) {
        self.key = key
        self.title = title
        self.category = category
        self.kind = kind
        self.byteChange = byteChange
        self.currentBytes = currentBytes
        self.risk = risk
        self.explanation = explanation
        self.isActionable = isActionable
        self.origin = origin
        self.provider = provider
        self.ruleID = ruleID
        self.ruleVersion = ruleVersion
        self.applicationAssociations = applicationAssociations
    }
}

public struct StorageSnapshotReport: Sendable {
    public let current: StorageSnapshot?
    public let previous: StorageSnapshot?
    public let history: [StorageSnapshot]
    public let changes: [StorageChange]

    public init(current: StorageSnapshot?, previous: StorageSnapshot?, history: [StorageSnapshot], changes: [StorageChange]) {
        self.current = current
        self.previous = previous
        self.history = history
        self.changes = changes
    }

    public static let empty = StorageSnapshotReport(current: nil, previous: nil, history: [], changes: [])
    public var isFirstSnapshot: Bool { current != nil && previous == nil }
    public var reclaimableBytes: Int64 {
        guard let current else { return 0 }

        let actionableEntries = current.entries.filter(\.isActionable)
        return actionableEntries.reduce(0) { totalBytes, entry in
            totalBytes + entry.byteSize
        }
    }
    public var availableSpaceChange: Int64? {
        guard let current, let previous else { return nil }
        return current.availableBytes - previous.availableBytes
    }

    public var categorySummaries: [StorageCategorySummary] {
        guard let current else { return [] }
        let grouped = Dictionary(grouping: current.entries.filter(\.countsTowardCategoryTotal), by: { StorageCategory.fromStoredTitle($0.category) })
        return grouped.map { category, entries in
            StorageCategorySummary(category: category, byteSize: entries.reduce(0) { $0 + $1.byteSize }, entryCount: entries.count)
        }
        .sorted { $0.byteSize > $1.byteSize }
    }

    public var categoryChanges: [StorageCategoryChange] {
        guard let current, let previous else { return [] }
        let currentTotals = totalsByCategory(for: current.entries)
        let previousTotals = totalsByCategory(for: previous.entries)
        let categories = Set(currentTotals.keys).union(previousTotals.keys)
        let minimumMeaningfulChange: Int64 = 1_024 * 1_024
        return categories.compactMap { category in
            let currentBytes = currentTotals[category, default: 0]
            let byteChange = currentBytes - previousTotals[category, default: 0]
            guard abs(byteChange) >= minimumMeaningfulChange else { return nil }
            return StorageCategoryChange(category: category, byteChange: byteChange, currentBytes: currentBytes)
        }
        .sorted { abs($0.byteChange) > abs($1.byteChange) }
    }

    public var applicationChanges: [ApplicationChange] {
        guard let current, let previous else { return [] }
        let currentTotals = totalsByApplication(for: current.entries)
        let previousTotals = totalsByApplication(for: previous.entries)
        let identities = currentTotals.identities.merging(previousTotals.identities) { current, _ in current }
        let identifiers = Set(currentTotals.bytes.keys).union(previousTotals.bytes.keys)
        let minimumMeaningfulChange: Int64 = 1_024 * 1_024
        return identifiers.compactMap { identifier in
            let currentBytes = currentTotals.bytes[identifier, default: 0]
            let byteChange = currentBytes - previousTotals.bytes[identifier, default: 0]
            guard abs(byteChange) >= minimumMeaningfulChange, let identity = identities[identifier] else { return nil }
            return ApplicationChange(
                identity: identity,
                byteChange: byteChange,
                currentBytes: currentBytes,
                entryChanges: changes(forApplicationID: identifier)
            )
        }
        .sorted { abs($0.byteChange) > abs($1.byteChange) }
    }

    private func totalsByCategory(for entries: [StorageSnapshotEntry]) -> [StorageCategory: Int64] {
        Dictionary(grouping: entries.filter(\.countsTowardCategoryTotal), by: { StorageCategory.fromStoredTitle($0.category) })
            .mapValues { $0.reduce(0) { $0 + $1.byteSize } }
    }

    private func totalsByApplication(for entries: [StorageSnapshotEntry]) -> (bytes: [String: Int64], identities: [String: ApplicationIdentity]) {
        var bytes: [String: Int64] = [:]
        var identities: [String: ApplicationIdentity] = [:]
        for entry in entries {
            for association in entry.applicationAssociations {
                bytes[association.application.id, default: 0] += entry.byteSize
                identities[association.application.id] = association.application
            }
        }
        return (bytes, identities)
    }

    private func changes(forApplicationID applicationID: String) -> [StorageChange] {
        let currentAssociations = Dictionary(uniqueKeysWithValues: (current?.entries ?? []).map {
            ($0.key, Set($0.applicationAssociations.map(\.application.id)))
        })
        let previousAssociations = Dictionary(uniqueKeysWithValues: (previous?.entries ?? []).map {
            ($0.key, Set($0.applicationAssociations.map(\.application.id)))
        })
        return changes.filter { change in
            currentAssociations[change.key]?.contains(applicationID) == true ||
                previousAssociations[change.key]?.contains(applicationID) == true
        }
    }
}

public struct StorageCategorySummary: Identifiable, Sendable {
    public let category: StorageCategory
    public let byteSize: Int64
    public let entryCount: Int
    public var id: StorageCategory { category }
}

public struct StorageCategoryChange: Identifiable, Sendable {
    public let category: StorageCategory
    public let byteChange: Int64
    public let currentBytes: Int64
    public var id: StorageCategory { category }
}

public struct ApplicationChange: Identifiable, Sendable {
    public let identity: ApplicationIdentity
    public let byteChange: Int64
    public let currentBytes: Int64
    public let entryChanges: [StorageChange]

    public var id: String { identity.id }

    public init(
        identity: ApplicationIdentity,
        byteChange: Int64,
        currentBytes: Int64,
        entryChanges: [StorageChange]
    ) {
        self.identity = identity
        self.byteChange = byteChange
        self.currentBytes = currentBytes
        self.entryChanges = entryChanges
    }
}
