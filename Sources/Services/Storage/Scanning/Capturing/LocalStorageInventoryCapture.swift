import Foundation
import SecondWindCore
import SecondWindApplication

/// Builds an inventory from provider facts and delegates only conflicts to the
/// reconciler. This is the underlying system operation, not a repository.
public struct LocalStorageInventoryCapture: StorageInventoryCapture {
    private let reconciler: any StorageInventoryReconciler

    public init(reconciler: any StorageInventoryReconciler = DefaultStorageInventoryReconciler()) {
        self.reconciler = reconciler
    }

    public func capture(_ results: [ScanProviderResult], capturedAt: Date = Date()) -> StorageInventory {
        let observations = results.flatMap(\.observations)
        let grouped = Dictionary(grouping: observations, by: \.identity)
        var conflictingIdentities = Set(grouped.filter { $0.value.count > 1 }.map(\.key))
        let identities = Array(grouped.keys)
        for (index, identity) in identities.enumerated() {
            for candidate in identities.dropFirst(index + 1) where overlaps(identity, candidate) {
                conflictingIdentities.insert(identity)
                conflictingIdentities.insert(candidate)
            }
        }
        let direct = grouped
            .filter { !conflictingIdentities.contains($0.key) }
            .flatMap(\.value)
            .map { StorageInventoryEntry($0) }
        let conflicts = observations.filter { conflictingIdentities.contains($0.identity) }
        return StorageInventory(capturedAt: capturedAt, entries: direct + reconciler.reconcile(conflicts))
    }

    private func overlaps(_ left: StorageIdentity, _ right: StorageIdentity) -> Bool {
        guard left.volumeID == right.volumeID, left.resolvedPath != right.resolvedPath else { return false }
        return left.resolvedPath.hasPrefix(right.resolvedPath + "/") || right.resolvedPath.hasPrefix(left.resolvedPath + "/")
    }
}
