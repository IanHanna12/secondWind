import Foundation

/// Discovers metadata from locally installed application bundles.
public protocol ApplicationDiscovering: Sendable {
    func discoverApplications() -> [InstalledApplication]
}

/// Attaches explainable application relationships to known inventory entries.
/// Implementations must not change an entry's risk or cleanup eligibility.
public protocol ApplicationAssociationResolving: Sendable {
    func resolve(inventory: StorageInventory, applications: [InstalledApplication]) -> StorageInventory
}

/// Builds the application-focused projection from the canonical inventory.
public protocol ApplicationInventoryBuilding: Sendable {
    func build(storageInventory: StorageInventory, applications: [InstalledApplication]) -> ApplicationInventory
}

public struct ApplicationInventoryBuilder: ApplicationInventoryBuilding {
    public init() {}

    public func build(storageInventory: StorageInventory, applications: [InstalledApplication]) -> ApplicationInventory {
        ApplicationInventory(storageInventory: storageInventory, applications: applications)
    }
}
