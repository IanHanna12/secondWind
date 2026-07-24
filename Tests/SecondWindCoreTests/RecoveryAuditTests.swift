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
    }
}
