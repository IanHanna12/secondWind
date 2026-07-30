import Foundation
import SecondWindCore
import SecondWindApplication

/// Resolves the exceptional cases identified by StorageInventoryCapture. It
/// never performs ordinary inventory construction.
public struct DefaultStorageInventoryReconciler: StorageInventoryReconciler {
    public init() {}

    public func reconcile(_ observations: [StorageObservation]) -> [StorageInventoryEntry] {
        let samePath = Dictionary(grouping: observations, by: \.identity)
        let entries: [StorageInventoryEntry] = samePath.values.map(reconcileSamePath)
        let parentPaths = Set(entries.compactMap(\.path).filter { parent in
            entries.compactMap(\.path).contains { child in child != parent && child.hasPrefix(parent + "/") }
        })
        return entries.map { entry in
            guard let path = entry.path, !parentPaths.contains(path),
                  parentPaths.contains(where: { path.hasPrefix($0 + "/") }) else { return entry }
            return StorageInventoryEntry(
                key: entry.key,
                title: entry.title,
                path: entry.path,
                category: entry.category,
                byteSize: entry.byteSize,
                origin: entry.origin,
                explanation: entry.explanation,
                risk: entry.risk,
                isActionable: entry.isActionable,
                countsTowardCategoryTotal: false,
                modifiedAt: entry.modifiedAt,
                applicationAssociations: entry.applicationAssociations,
                identity: entry.identity,
                ruleID: entry.ruleID,
                ruleVersion: entry.ruleVersion,
                provider: entry.provider,
                discoveryConfidence: entry.discoveryConfidence,
                supportedAction: entry.supportedAction
            )
        }
    }

    private func reconcileSamePath(_ observations: [StorageObservation]) -> StorageInventoryEntry {
        guard let preferredObservation = preferredObservation(in: observations) else {
            preconditionFailure("A same-path reconciliation needs at least one observation.")
        }

        let strictestRisk = strictestRisk(in: observations)
        let supportedAction = supportedAction(for: observations, risk: strictestRisk)
        let combinedOrigins = combinedOrigins(from: observations)
        let combinedProviders = combinedProviders(from: observations)
        let combinedAssociations = combinedAssociations(from: observations)
        let largestObservedSize = largestObservedSize(in: observations)
        let latestModificationDate = latestModificationDate(in: observations)
        let strongestDiscoveryConfidence = strongestDiscoveryConfidence(in: observations)

        return StorageInventoryEntry(
            key: "storage|\(preferredObservation.identity.volumeID)|\(preferredObservation.identity.resolvedPath)",
            title: preferredObservation.title,
            path: preferredObservation.identity.resolvedPath,
            category: preferredObservation.category,
            byteSize: largestObservedSize,
            origin: combinedOrigins,
            explanation: preferredObservation.explanation,
            risk: strictestRisk,
            isActionable: strictestRisk.isExecutable && supportedAction != .none,
            modifiedAt: latestModificationDate,
            applicationAssociations: combinedAssociations,
            identity: preferredObservation.identity,
            ruleID: preferredObservation.ruleID,
            ruleVersion: preferredObservation.ruleVersion,
            provider: combinedProviders,
            discoveryConfidence: strongestDiscoveryConfidence,
            supportedAction: supportedAction
        )
    }

    private func preferredObservation(in observations: [StorageObservation]) -> StorageObservation? {
        observations.min { leftObservation, rightObservation in
            let leftRiskRank = riskRank(leftObservation.risk)
            let rightRiskRank = riskRank(rightObservation.risk)

            if leftRiskRank != rightRiskRank {
                return leftRiskRank > rightRiskRank
            }

            return leftObservation.origin < rightObservation.origin
        }
    }

    private func strictestRisk(in observations: [StorageObservation]) -> Risk {
        observations.map(\.risk).max { leftRisk, rightRisk in
            riskRank(leftRisk) < riskRank(rightRisk)
        } ?? .protected
    }

    private func supportedAction(for observations: [StorageObservation], risk: Risk) -> SupportedAction {
        guard risk != .protected else { return .none }

        let actions = observations.map(\.supportedAction)
        if actions.contains(.none) {
            return .none
        }
        if actions.contains(.uninstall) {
            return .uninstall
        }
        return .cleanup
    }

    private func combinedOrigins(from observations: [StorageObservation]) -> String {
        uniqueSortedValues(observations.map(\.origin)).joined(separator: " • ")
    }

    private func combinedProviders(from observations: [StorageObservation]) -> String {
        uniqueSortedValues(observations.map(\.provider)).joined(separator: " • ")
    }

    private func largestObservedSize(in observations: [StorageObservation]) -> Int64 {
        observations.map(\.byteSize).max() ?? 0
    }

    private func latestModificationDate(in observations: [StorageObservation]) -> Date? {
        observations.compactMap(\.modifiedAt).max()
    }

    private func strongestDiscoveryConfidence(in observations: [StorageObservation]) -> StorageDiscoveryConfidence {
        observations.map(\.discoveryConfidence).max { leftConfidence, rightConfidence in
            confidenceRank(leftConfidence) < confidenceRank(rightConfidence)
        } ?? .low
    }

    private func combinedAssociations(from observations: [StorageObservation]) -> [ApplicationAssociation] {
        let associations = observations.flatMap(\.applicationAssociations)
        var associatedApplicationIDs = Set<String>()

        return associations.filter { association in
            associatedApplicationIDs.insert(association.application.id).inserted
        }
    }

    private func uniqueSortedValues(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    private func riskRank(_ risk: Risk) -> Int {
        switch risk {
        case .safe:
            return 0
        case .reviewRequired:
            return 1
        case .protected:
            return 2
        }
    }

    private func confidenceRank(_ confidence: StorageDiscoveryConfidence) -> Int {
        switch confidence {
        case .low:
            return 0
        case .medium:
            return 1
        case .high:
            return 2
        }
    }
}
