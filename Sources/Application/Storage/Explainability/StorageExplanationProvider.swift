import Foundation
import SecondWindCore

/// A named provider of read-only explanations.
public protocol ExplanationProvider: Sendable {}

/// Builds explanations for the existing canonical storage inventory.
public protocol StorageExplanationProvider: ExplanationProvider {
    func explain(_ entry: StorageInventoryEntry) -> StorageInventoryExplanation
    func explain(inventory: StorageInventory) -> [StorageInventoryExplanation]
}

public struct DefaultStorageExplanationProvider: StorageExplanationProvider {
    public init() {}

    public func explain(_ entry: StorageInventoryEntry) -> StorageInventoryExplanation {
        StorageInventoryExplanation(
            entry: entry,
            facts: facts(for: entry),
            cleanupReasons: cleanupReasons(for: entry),
            protectionReasons: protectionReasons(for: entry),
            relationshipReasons: relationshipReasons(for: entry),
            journey: journey(for: entry)
        )
    }

    public func explain(inventory: StorageInventory) -> [StorageInventoryExplanation] {
        inventory.entries.map(explain)
    }

    private func facts(for entry: StorageInventoryEntry) -> [StorageExplanationFact] {
        var facts: [StorageExplanationFact] = [
            .init(title: "Path", value: entry.path ?? "No local path is available"),
            .init(title: "Category", value: entry.category.title, detail: entry.category.explanation),
            .init(title: "Observed by", value: entry.provider),
            .init(title: "Origin", value: entry.origin),
            .init(title: "Discovery confidence", value: entry.discoveryConfidence.title, detail: confidenceDetail(for: entry.discoveryConfidence)),
            .init(title: "Cleanup policy", value: policyDescription(entry.risk), detail: entry.explanation),
            .init(title: "Supported action", value: actionDescription(entry.supportedAction))
        ]

        if let ruleID = entry.ruleID {
            let version = entry.ruleVersion.map { " v\($0)" } ?? ""
            facts.append(.init(title: "Matched rule", value: "\(ruleID)\(version)"))
        } else {
            facts.append(.init(title: "Matched rule", value: "No cleanup rule"))
        }

        for association in entry.applicationAssociations {
            facts.append(.init(
                title: "Associated application",
                value: association.application.displayName,
                detail: "\(association.relationship.title) · \(association.evidence.title): \(association.reason)"
            ))
        }
        return facts
    }

    private func cleanupReasons(for entry: StorageInventoryEntry) -> [String] {
        guard entry.isActionable else { return [] }
        var reasons: [String] = []
        if let ruleID = entry.ruleID {
            let version = entry.ruleVersion.map { " v\($0)" } ?? ""
            reasons.append("Matches rule \(ruleID)\(version).")
        }
        reasons.append("Observed by \(entry.provider) inside a location Second Wind explicitly understands.")
        reasons.append(entry.explanation)
        switch entry.supportedAction {
        case .cleanup:
            reasons.append("Supports local Recovery and Finder Trash after review.")
        case .uninstall:
            reasons.append("Supports the reviewed application-removal workflow.")
        case .none:
            break
        }
        return reasons
    }

    private func protectionReasons(for entry: StorageInventoryEntry) -> [String] {
        guard !entry.isActionable else { return [] }
        var reasons = [entry.explanation]
        if entry.risk == .protected {
            reasons.append("Second Wind does not create a cleanup action for protected storage.")
        } else if entry.supportedAction == .none {
            reasons.append("No supported cleanup action exists for this location.")
        }
        if entry.applicationAssociations.contains(where: { $0.isShared }) {
            reasons.append("The location is shared by an application relationship and remains excluded from automatic eligibility.")
        }
        return reasons
    }

    private func relationshipReasons(for entry: StorageInventoryEntry) -> [String] {
        entry.applicationAssociations.map { association in
            "\(association.application.displayName): \(association.relationship.title) through \(association.evidence.title.lowercased()) evidence — \(association.reason)"
        }
    }

    private func journey(for entry: StorageInventoryEntry) -> [StorageJourneyStep] {
        var steps = [StorageJourneyStep(title: "Observed", detail: "\(entry.provider) recorded this local location.")]
        if let ruleID = entry.ruleID {
            let version = entry.ruleVersion.map { " v\($0)" } ?? ""
            steps.append(.init(title: "Matched rule", detail: "\(ruleID)\(version) supplied the policy facts."))
        }
        steps.append(.init(title: "Storage Inventory", detail: "The location is part of the current canonical inventory."))
        if !entry.applicationAssociations.isEmpty {
            steps.append(.init(title: "Application Inventory", detail: "Its observed application relationships are available for inspection."))
        }
        if entry.isActionable {
            steps.append(.init(title: "Cleanup review", detail: "The item can be deliberately selected for a reviewed cleanup plan."))
            steps.append(.init(title: "Recovery", detail: "A confirmed cleanup can keep the item in local Recovery for later restore."))
        } else {
            steps.append(.init(title: "Protected", detail: "The current policy does not allow this location into a cleanup plan."))
        }
        return steps
    }

    private func actionDescription(_ action: SupportedAction) -> String {
        switch action {
        case .none: return "No cleanup action"
        case .cleanup: return "Recovery or Finder Trash after review"
        case .uninstall: return "Reviewed application removal"
        }
    }

    private func confidenceDetail(for confidence: StorageDiscoveryConfidence) -> String {
        switch confidence {
        case .high:
            return "Observed through a known provider, built-in rule, or exact application identity."
        case .medium:
            return "Observed through a known path or supporting application metadata."
        case .low:
            return "Observed with limited evidence. This does not make the item eligible for cleanup."
        }
    }

    private func policyDescription(_ risk: Risk) -> String {
        switch risk {
        case .safe: return "Eligible after review"
        case .reviewRequired: return "Requires review"
        case .protected: return "Protected"
        }
    }
}
