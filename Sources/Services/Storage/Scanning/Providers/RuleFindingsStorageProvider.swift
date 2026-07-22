import Foundation
import SecondWindCore
import SecondWindApplication
import SecondWindMacOS

public struct RuleFindingsStorageProvider: StorageInventoryProvider {
    public let name = "Rules"
    private let fileSystem: any FileSystem

    public init(fileSystem: any FileSystem = LocalFileSystem()) { self.fileSystem = fileSystem }

    public func observe(request: StorageScanRequest, cancellationRequested: @escaping @Sendable () async -> Bool) async throws -> ScanProviderResult {
        let scanner = CleanupScanner(home: request.home, fileSystem: fileSystem, rules: request.rules)
        let outcome = scanner.scan { _ in !Task.isCancelled }
        if await cancellationRequested() || Task.isCancelled { throw OperationFailure.cancelled }
        guard case let .completed(findings) = outcome else { throw OperationFailure.cancelled }
        return ScanProviderResult(provider: name, observations: findings.map { finding in
            StorageObservation(identity: .init(volumeID: "local", resolvedPath: finding.path), title: finding.title, category: .forFindingCategory(finding.category), byteSize: finding.byteSize, origin: finding.origin, explanation: finding.explanation, risk: finding.risk, supportedAction: finding.supportedAction)
        })
    }
}
