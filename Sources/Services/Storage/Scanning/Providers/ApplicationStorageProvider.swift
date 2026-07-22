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
        return ScanProviderResult(provider: name, observations: applications.map { application in
            StorageObservation(identity: .init(volumeID: "local", resolvedPath: application.url.path), title: application.displayName, category: .applications, byteSize: fileSystem.fileSize(at: application.url), origin: "Application inventory", explanation: "Application bundle observed locally. Use Applications to inspect its exact support paths before creating a removal plan.", risk: .protected)
        })
    }
}
