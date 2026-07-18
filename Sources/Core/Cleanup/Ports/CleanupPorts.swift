import Foundation

/// The application layer depends on these capabilities, never on concrete disk or XPC services.
public protocol FileSystem: Sendable {
    func exists(_ url: URL) -> Bool
    func fileSize(at url: URL) -> Int64
    func directChildren(in root: URL) -> [URL]
    func regularFiles(in root: URL, maximumDepth: Int) -> [URL]
}

public protocol RecoveryRepository: Sendable {
    func storeInRecovery(_ sourceURL: URL, planID: UUID) throws -> RecoveryItem
    func allItems() -> [RecoveryItem]
    @discardableResult func restore(_ item: RecoveryItem) throws -> URL
    func deletePermanently(_ item: RecoveryItem) throws
}

public protocol AuditRecording: Sendable {
    func append(_ record: AuditRecord) throws
}

public protocol TrashMoving: Sendable {
    func moveToTrash(_ url: URL) async throws
}
