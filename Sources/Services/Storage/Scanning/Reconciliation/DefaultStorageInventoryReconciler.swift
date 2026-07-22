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
            return StorageInventoryEntry(key: entry.key, title: entry.title, path: entry.path, category: entry.category, byteSize: entry.byteSize, origin: entry.origin, explanation: entry.explanation, risk: entry.risk, isActionable: entry.isActionable, countsTowardCategoryTotal: false, modifiedAt: entry.modifiedAt, applicationAssociations: entry.applicationAssociations)
        }
    }

    private func reconcileSamePath(_ observations: [StorageObservation]) -> StorageInventoryEntry {
        let selected = observations.min { left, right in
            let leftRank = riskRank(left.risk)
            let rightRank = riskRank(right.risk)
            if leftRank != rightRank { return leftRank > rightRank }
            return left.origin < right.origin
        }!
        let risk = observations.map(\.risk).max { riskRank($0) < riskRank($1) } ?? selected.risk
        let supportedAction = risk == .protected ? .none : conservativeAction(observations.map(\.supportedAction))
        let origins = Array(Set(observations.map(\.origin))).sorted().joined(separator: " • ")
        let associations = uniqueAssociations(observations.flatMap(\.applicationAssociations))
        return StorageInventoryEntry(
            key: "storage|\(selected.identity.volumeID)|\(selected.identity.resolvedPath)", title: selected.title,
            path: selected.identity.resolvedPath, category: selected.category,
            byteSize: observations.map(\.byteSize).max() ?? 0, origin: origins,
            explanation: selected.explanation, risk: risk,
            isActionable: risk.isExecutable && supportedAction != .none,
            modifiedAt: observations.compactMap(\.modifiedAt).max(), applicationAssociations: associations
        )
    }

    private func riskRank(_ risk: Risk) -> Int { switch risk { case .safe: return 0; case .reviewRequired: return 1; case .protected: return 2 } }
    private func conservativeAction(_ actions: [SupportedAction]) -> SupportedAction { actions.contains(.none) ? .none : (actions.contains(.uninstall) ? .uninstall : .cleanup) }
    private func uniqueAssociations(_ associations: [ApplicationAssociation]) -> [ApplicationAssociation] {
        var seen = Set<String>()
        return associations.filter { seen.insert($0.application.id).inserted }
    }
}
