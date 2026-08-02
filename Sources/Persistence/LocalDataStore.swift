import Foundation
import SecondWindCore

/// The app's one local persistence entry point. Each nested store owns one
/// durable document or Recovery payload layout; callers do not construct or
/// coordinate those storage details independently.
public struct LocalDataStore: Store, @unchecked Sendable {
    public let audit: AuditStore
    public let recovery: RecoveryStore
    public let rulePolicy: RulePolicyStore
    public let snapshots: StorageSnapshotStore

    public init(
        audit: AuditStore = AuditStore(),
        recovery: RecoveryStore = RecoveryStore(),
        rulePolicy: RulePolicyStore = RulePolicyStore(),
        snapshots: StorageSnapshotStore = StorageSnapshotStore()
    ) {
        self.audit = audit
        self.recovery = recovery
        self.rulePolicy = rulePolicy
        self.snapshots = snapshots
    }
}

/// Stable envelope shared by Second Wind's durable JSON documents. Stores
/// decode their legacy payloads in memory and write this envelope only after a
/// later operation succeeds, so merely launching a newer app never rewrites
/// user data.
struct VersionedDocument<Payload: Codable>: Codable {
    let schemaVersion: Int
    let payload: Payload
}

struct PersistenceDocumentHeader: Decodable {
    let schemaVersion: Int
}

public enum PersistenceDocumentError: LocalizedError, Equatable, Sendable {
    case corrupt(document: String)
    case unsupportedFutureVersion(document: String, version: Int)

    public var errorDescription: String? {
        switch self {
        case let .corrupt(document):
            return "The stored \(document) document is damaged. It was left untouched."
        case let .unsupportedFutureVersion(document, version):
            return "The stored \(document) document uses unsupported schema version \(version). It was left untouched."
        }
    }
}

enum PersistenceDocumentCodec {
    static let currentSchemaVersion = 1

    static func decode<Payload: Codable>(
        _ payloadType: Payload.Type,
        from data: Data,
        documentName: String,
        legacy: () throws -> Payload
    ) throws -> Payload {
        let decoder = JSONDecoder.secondWind

        if let header = try? decoder.decode(PersistenceDocumentHeader.self, from: data) {
            guard header.schemaVersion <= currentSchemaVersion else {
                throw PersistenceDocumentError.unsupportedFutureVersion(
                    document: documentName,
                    version: header.schemaVersion
                )
            }
            do {
                return try decoder.decode(VersionedDocument<Payload>.self, from: data).payload
            } catch {
                throw PersistenceDocumentError.corrupt(document: documentName)
            }
        }

        do {
            return try legacy()
        } catch {
            throw PersistenceDocumentError.corrupt(document: documentName)
        }
    }

    static func encode<Payload: Codable>(_ payload: Payload) throws -> Data {
        try JSONEncoder.secondWind.encode(
            VersionedDocument(schemaVersion: currentSchemaVersion, payload: payload)
        )
    }

    static func encodeLine<Payload: Codable>(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder.secondWind
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(
            VersionedDocument(schemaVersion: currentSchemaVersion, payload: payload)
        )
    }
}
