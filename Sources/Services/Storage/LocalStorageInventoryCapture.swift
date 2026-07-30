import Foundation
import SecondWindCore
import SecondWindApplication

/// Builds an inventory from provider facts and delegates only ambiguous facts
/// to the reconciler. This is an underlying system operation, not a repository.
public struct LocalStorageInventoryCapture: StorageInventoryCapture {
    private let reconciler: any StorageInventoryReconciler

    public init(reconciler: any StorageInventoryReconciler = DefaultStorageInventoryReconciler()) {
        self.reconciler = reconciler
    }

    public func capture(_ results: [ScanProviderResult], capturedAt: Date = Date()) -> StorageInventory {
        let observations = results.flatMap(\.observations)
        let observationsByIdentity = Dictionary(grouping: observations, by: \.identity)
        let identitiesNeedingReconciliation = identitiesNeedingReconciliation(
            in: observationsByIdentity
        )

        let directEntries = observations
            .filter { !identitiesNeedingReconciliation.contains($0.identity) }
            .map { StorageInventoryEntry($0) }
        let observationsNeedingReconciliation = observations.filter {
            identitiesNeedingReconciliation.contains($0.identity)
        }
        let reconciledEntries = observationsNeedingReconciliation.isEmpty
            ? []
            : reconciler.reconcile(observationsNeedingReconciliation)

        return StorageInventory(
            capturedAt: capturedAt,
            entries: directEntries + reconciledEntries
        )
    }

    /// Reconciliation is needed only when providers describe one location
    /// more than once or when one described path contains another.
    private func identitiesNeedingReconciliation(
        in observationsByIdentity: [StorageIdentity: [StorageObservation]]
    ) -> Set<StorageIdentity> {
        var identitiesNeedingReconciliation = Set<StorageIdentity>()

        for (identity, observations) in observationsByIdentity where observations.count > 1 {
            identitiesNeedingReconciliation.insert(identity)
        }

        let identities = Array(observationsByIdentity.keys)
        for leftIndex in identities.indices.dropLast() {
            let leftIdentity = identities[leftIndex]
            for rightIdentity in identities[(leftIndex + 1)...] where pathsOverlap(leftIdentity, rightIdentity) {
                identitiesNeedingReconciliation.insert(leftIdentity)
                identitiesNeedingReconciliation.insert(rightIdentity)
            }
        }

        return identitiesNeedingReconciliation
    }

    private func pathsOverlap(_ left: StorageIdentity, _ right: StorageIdentity) -> Bool {
        guard left.volumeID == right.volumeID, left.resolvedPath != right.resolvedPath else { return false }
        return left.resolvedPath.hasPrefix(right.resolvedPath + "/")
            || right.resolvedPath.hasPrefix(left.resolvedPath + "/")
    }
}
