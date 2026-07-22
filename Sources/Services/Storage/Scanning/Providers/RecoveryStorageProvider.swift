import Foundation
import SecondWindCore
import SecondWindApplication

public struct RecoveryStorageProvider: StorageInventoryProvider {
    public let name = "Recovery"
    public init() {}

    public func observe(request: StorageScanRequest, cancellationRequested: @escaping @Sendable () async -> Bool) async throws -> ScanProviderResult {
        if await cancellationRequested() || Task.isCancelled { throw OperationFailure.cancelled }
        return ScanProviderResult(provider: name, observations: request.recoveryItems.map { item in
            StorageObservation(identity: .init(volumeID: "local", resolvedPath: item.recoveryPath), title: "Recovery: \(URL(fileURLWithPath: item.originalPath).lastPathComponent)", category: .recovery, byteSize: item.byteSize, origin: "Second Wind Recovery", explanation: "Stored locally by Second Wind. It remains recoverable until you choose to restore or delete it.", risk: .protected)
        })
    }
}
