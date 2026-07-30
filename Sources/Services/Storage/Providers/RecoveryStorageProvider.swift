import Foundation
import SecondWindCore
import SecondWindApplication
import SecondWindMacOS

public struct RecoveryStorageProvider: StorageInventoryProvider {
    public let name = "Recovery"
    private let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem = LocalFileSystem()) {
        self.fileSystem = fileSystem
    }

    public func observe(request: StorageScanRequest, cancellationRequested: @escaping @Sendable () async -> Bool) async throws -> ScanProviderResult {
        if await cancellationRequested() || Task.isCancelled { throw OperationFailure.cancelled }
        return ScanProviderResult(provider: name, observations: request.recoveryItems.map { item in
            StorageObservation(
                identity: .init(volumeID: "local", resolvedPath: item.recoveryPath),
                title: "Recovery: \(LocalPathDisplay.name(for: item.originalPath))",
                category: .recovery,
                byteSize: fileSystem.allocatedSize(at: URL(fileURLWithPath: item.recoveryPath)),
                origin: "Second Wind Recovery",
                explanation: "Stored locally by Second Wind. It remains recoverable until you choose to restore or delete it.",
                risk: .protected,
                ruleID: item.context.ruleID,
                ruleVersion: item.context.ruleVersion.flatMap(Int.init),
                provider: name,
                discoveryConfidence: .high
            )
        })
    }
}
