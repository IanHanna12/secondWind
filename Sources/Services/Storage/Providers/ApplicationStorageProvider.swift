import Foundation
import SecondWindCore
import SecondWindApplication
import SecondWindMacOS

public struct ApplicationStorageProvider: StorageInventoryProvider {
    public let name = "Applications"
    private let discoverApplications: @Sendable (URL) -> [InstalledApplication]
    private let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem = LocalFileSystem(), discoverApplications: @escaping @Sendable (URL) -> [InstalledApplication] = { InstalledApplicationInventory(home: $0).discoverApplications() }) {
        self.fileSystem = fileSystem
        self.discoverApplications = discoverApplications
    }

    public func observe(request: StorageScanRequest, cancellationRequested: @escaping @Sendable () async -> Bool) async throws -> ScanProviderResult {
        if await cancellationRequested() || Task.isCancelled { throw OperationFailure.cancelled }
        let applications = discoverApplications(request.home)
        if await cancellationRequested() || Task.isCancelled { throw OperationFailure.cancelled }
        let applicationObservations = applications.map { application in
            StorageObservation(
                identity: .init(volumeID: "local", resolvedPath: application.url.path),
                title: application.displayName,
                category: .applications,
                byteSize: fileSystem.allocatedSize(at: application.url),
                origin: "Application inventory",
                explanation: "Application bundle observed locally. Use Applications to inspect its exact support paths before creating a removal plan.",
                risk: .protected,
                provider: name,
                discoveryConfidence: .high
            )
        }
        let storageDiscovery = ApplicationStorageDiscovery(home: request.home)
        let supportObservations = storageDiscovery.inventoryEntries(for: applications).map(storageObservation)
        let orphanFindings = storageDiscovery.orphanCleanupFindings(for: applications)
        return ScanProviderResult(
            provider: name,
            observations: applicationObservations + supportObservations,
            findings: orphanFindings,
            applications: applications
        )
    }

    private func storageObservation(from entry: StorageInventoryEntry) -> StorageObservation {
        StorageObservation(
            identity: .init(volumeID: "local", resolvedPath: entry.path ?? entry.key),
            title: entry.title,
            category: entry.category,
            byteSize: entry.byteSize,
            origin: entry.origin,
            explanation: entry.explanation,
            risk: entry.risk,
            supportedAction: entry.isActionable ? .cleanup : .none,
            modifiedAt: entry.modifiedAt,
            applicationAssociations: entry.applicationAssociations,
            ruleID: entry.ruleID,
            ruleVersion: entry.ruleVersion,
            provider: name,
            discoveryConfidence: entry.discoveryConfidence
        )
    }
}
