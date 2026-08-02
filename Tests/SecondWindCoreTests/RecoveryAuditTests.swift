import Foundation
import XCTest
@testable import SecondWindCore
@testable import SecondWindPersistence

final class RecoveryAuditTests: XCTestCase {
    func testLegacyManifestDecodesWithRecoveryPath() throws {
        let itemID = UUID()
        let planID = UUID()
        let manifest = """
        {"id":"\(itemID.uuidString)","planID":"\(planID.uuidString)","originalPath":"/tmp/report.txt","quarantinedPath":"/tmp/Recovery/payload/report.txt","createdAt":"2026-01-01T00:00:00Z","byteSize":42}
        """

        let item = try JSONDecoder.secondWind.decode(RecoveryItem.self, from: Data(manifest.utf8))

        XCTAssertEqual(item.recoveryPath, "/tmp/Recovery/payload/report.txt")
    }

    func testRecoveryManifestUsesTheStableSchemaEnvelope() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("report.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("stored".utf8).write(to: source)

        let store = RecoveryStore(root: root.appendingPathComponent("Recovery"))
        let item = try store.storeInRecovery(source, planID: UUID())
        let manifestURL = store.root.appendingPathComponent(item.id.uuidString).appendingPathComponent("manifest.json")
        let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])

        XCTAssertEqual(document["schemaVersion"] as? Int, 1)
        XCTAssertTrue(store.integrityReport(for: item).canRestore)
    }

    func testLegacyRecoveryManifestRemainsRestorable() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("report.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("stored".utf8).write(to: source)

        let store = RecoveryStore(root: root.appendingPathComponent("Recovery"))
        let item = try store.storeInRecovery(source, planID: UUID())
        let manifestURL = store.root.appendingPathComponent(item.id.uuidString).appendingPathComponent("manifest.json")
        try JSONEncoder.secondWind.encode(item).write(to: manifestURL, options: .atomic)

        XCTAssertEqual(store.allItems().map(\.id), [item.id])
        XCTAssertTrue(store.integrityReport(for: item).canRestore)
    }

    func testFutureRecoveryManifestStaysVisibleAsDamagedAndUntouched() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("report.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("stored".utf8).write(to: source)

        let store = RecoveryStore(root: root.appendingPathComponent("Recovery"))
        let item = try store.storeInRecovery(source, planID: UUID())
        let manifestURL = store.root.appendingPathComponent(item.id.uuidString).appendingPathComponent("manifest.json")
        let futureDocument = Data("{\"schemaVersion\":999,\"payload\":{}}".utf8)
        try futureDocument.write(to: manifestURL, options: .atomic)

        let report = store.integrityReport(for: item)
        XCTAssertFalse(report.canRestore)
        XCTAssertEqual(try Data(contentsOf: manifestURL), futureDocument)
        XCTAssertTrue(FileManager.default.fileExists(atPath: item.recoveryPath))
        XCTAssertEqual(store.allItems().map(\.id), [item.id])
    }

    func testMissingManifestRemainsVisibleAndCanOnlyDeleteItsContainedPayload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("report.txt")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("stored".utf8).write(to: source)

        let store = RecoveryStore(root: root.appendingPathComponent("Recovery"))
        let item = try store.storeInRecovery(source, planID: UUID())
        let manifestURL = store.root.appendingPathComponent(item.id.uuidString).appendingPathComponent("manifest.json")
        try FileManager.default.removeItem(at: manifestURL)

        let damagedItem = try XCTUnwrap(store.allItems().first)
        XCTAssertEqual(damagedItem.id, item.id)
        XCTAssertEqual(damagedItem.originalPath, "Original location unavailable")
        XCTAssertFalse(store.integrityReport(for: damagedItem).canRestore)
        XCTAssertThrowsError(try store.restore(damagedItem))

        try store.deletePermanently(damagedItem)
        XCTAssertTrue(store.allItems().isEmpty)
    }

    func testLegacyAuditMigratesToVersionedJSONLinesOnAppend() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("audit.jsonl")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let legacy = AuditRecord(kind: .scan, ruleVersions: [], paths: [], bytes: 0, result: "completed: legacy")
        let legacyEncoder = JSONEncoder()
        legacyEncoder.dateEncodingStrategy = .iso8601
        try legacyEncoder.encode(legacy).write(to: url)

        let store = AuditStore(fileURL: url)
        XCTAssertEqual(try store.loadRecords().map(\.id), [legacy.id])
        try store.append(.init(kind: .maintenance, ruleVersions: [], paths: [], bytes: 0, result: "next"))

        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        for line in lines {
            let document = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
            XCTAssertEqual(document["schemaVersion"] as? Int, 1)
        }
    }

    func testFutureAuditSchemaBlocksAppendWithoutChangingTheDocument() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("audit.jsonl")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let futureDocument = Data("{\"schemaVersion\":999,\"payload\":{}}\n".utf8)
        try futureDocument.write(to: url)
        let store = AuditStore(fileURL: url)

        XCTAssertThrowsError(try store.append(.init(kind: .maintenance, ruleVersions: [], paths: [], bytes: 0, result: "next")))
        XCTAssertEqual(try Data(contentsOf: url), futureDocument)
    }

    func testRestoreCollisionUsesDescriptiveRecoveryName() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Reports/report.txt")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stored".utf8).write(to: source)

        let store = RecoveryStore(root: root.appendingPathComponent("Recovery"))
        let item = try store.storeInRecovery(source, planID: UUID())
        try Data("current".utf8).write(to: source)

        let restored = try store.restore(item)

        XCTAssertTrue(restored.lastPathComponent.hasPrefix("report (Restored from Recovery — "))
        XCTAssertTrue(restored.lastPathComponent.hasSuffix(" UTC).txt"))
        XCTAssertEqual(try Data(contentsOf: restored), Data("stored".utf8))
        XCTAssertEqual(try Data(contentsOf: source), Data("current".utf8))
    }

    func testRestoreRejectsManifestPayloadOutsideItsRecoveryFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Reports/report.txt")
        let foreignPayload = root.appendingPathComponent("foreign.txt")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stored".utf8).write(to: source)
        try Data("foreign".utf8).write(to: foreignPayload)

        let store = RecoveryStore(root: root.appendingPathComponent("Recovery"))
        let item = try store.storeInRecovery(source, planID: UUID())
        let forged = RecoveryItem(id: item.id, planID: item.planID, originalPath: item.originalPath, recoveryPath: foreignPayload.path, createdAt: item.createdAt, byteSize: item.byteSize)

        XCTAssertThrowsError(try store.restore(forged)) { error in
            guard case RecoveryError.invalidItem = error else {
                return XCTFail("Expected invalid recovery item, got \(error)")
            }
        }
        XCTAssertThrowsError(try store.deletePermanently(forged)) { error in
            guard case RecoveryError.invalidItem = error else {
                return XCTFail("Expected invalid recovery item, got \(error)")
            }
        }
        XCTAssertEqual(try Data(contentsOf: foreignPayload), Data("foreign".utf8))
    }

    func testPermanentDeleteRemovesOnlyTheStoredRecoveryItem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Caches/cache.bin")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stored".utf8).write(to: source)

        let store = RecoveryStore(root: root.appendingPathComponent("Recovery"))
        let item = try store.storeInRecovery(source, planID: UUID())

        try store.deletePermanently(item)

        XCTAssertFalse(FileManager.default.fileExists(atPath: item.recoveryPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(store.allItems().isEmpty)
    }

    func testBatchRestoreRestoresEveryPreflightedItem() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstSource = root.appendingPathComponent("Caches/first.bin")
        let secondSource = root.appendingPathComponent("Caches/second.bin")
        try FileManager.default.createDirectory(at: firstSource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)

        let store = RecoveryStore(root: root.appendingPathComponent("Recovery"))
        let first = try store.storeInRecovery(firstSource, planID: UUID())
        let second = try store.storeInRecovery(secondSource, planID: UUID())

        let outcome = store.restore([first, second], choice: .besideExisting)

        XCTAssertEqual(outcome.action, .restore)
        XCTAssertEqual(outcome.completedCount, 2)
        XCTAssertEqual(outcome.requiresAttentionCount, 0)
        XCTAssertEqual(try Data(contentsOf: firstSource), Data("first".utf8))
        XCTAssertEqual(try Data(contentsOf: secondSource), Data("second".utf8))
        XCTAssertTrue(store.allItems().isEmpty)
    }

    func testBatchRestoreDoesNotStartWhenAnySelectedItemFailsIntegrity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let firstSource = root.appendingPathComponent("Caches/first.bin")
        let secondSource = root.appendingPathComponent("Caches/second.bin")
        try FileManager.default.createDirectory(at: firstSource.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)

        let store = RecoveryStore(root: root.appendingPathComponent("Recovery"))
        let first = try store.storeInRecovery(firstSource, planID: UUID())
        let second = try store.storeInRecovery(secondSource, planID: UUID())
        try FileManager.default.removeItem(at: URL(fileURLWithPath: second.recoveryPath))

        let outcome = store.restore([first, second], choice: .besideExisting)

        XCTAssertEqual(outcome.completedCount, 0)
        XCTAssertEqual(outcome.results.count, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstSource.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.recoveryPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: secondSource.path))
    }

    func testSingleConfirmedReplacementRestoresRecoveryPayload() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("Reports/report.txt")
        try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("stored".utf8).write(to: source)

        let store = RecoveryStore(root: root.appendingPathComponent("Recovery"))
        let item = try store.storeInRecovery(source, planID: UUID())
        try Data("current".utf8).write(to: source)

        let outcome = store.restore([item], choice: .replaceAfterDestructiveConfirmation)

        XCTAssertEqual(outcome.completedCount, outcome.results.count)
        XCTAssertEqual(try Data(contentsOf: source), Data("stored".utf8))
        XCTAssertTrue(store.allItems().isEmpty)
        let remainingNames = try FileManager.default.contentsOfDirectory(atPath: source.deletingLastPathComponent().path)
        XCTAssertFalse(remainingNames.contains { $0.hasPrefix(".secondwind-replacement-backup-") })
    }
}
