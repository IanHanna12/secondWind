import Foundation
import SecondWindCore
import SecondWindApplication
import SecondWindMacOS

public struct PersonalFoldersStorageProvider: StorageInventoryProvider {
    public let name = "Personal folders"
    private let fileSystem: any FileSystem

    public init(fileManager: FileManager = .default, fileSystem: (any FileSystem)? = nil) {
        self.fileSystem = fileSystem ?? LocalFileSystem(fileManager: fileManager)
    }

    public func observe(request: StorageScanRequest, cancellationRequested: @escaping @Sendable () async -> Bool) async throws -> ScanProviderResult {
        let roots: [(String, String, StorageCategory)] = [("Downloads", "Downloads", .downloads), ("Documents", "Documents", .documents), ("Desktop", "Desktop", .documents)]
        var observations: [StorageObservation] = []
        for (title, relativePath, category) in roots {
            if await cancellationRequested() || Task.isCancelled { throw OperationFailure.cancelled }
            let url = request.home.appendingPathComponent(relativePath)
            guard fileSystem.exists(url) else { continue }
            observations.append(StorageObservation(
                identity: .init(volumeID: "local", resolvedPath: url.path),
                title: title,
                category: category,
                byteSize: fileSystem.allocatedSize(at: url),
                origin: "Known personal folder",
                explanation: "Second Wind observes this known folder but never treats the folder itself as a cleanup candidate.",
                risk: .protected,
                provider: name,
                discoveryConfidence: .high
            ))
        }
        return ScanProviderResult(provider: name, observations: observations)
    }
}
