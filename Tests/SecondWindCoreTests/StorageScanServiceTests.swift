import Foundation
import XCTest
@testable import SecondWindCore
@testable import SecondWindPersistence
@testable import SecondWindServices

final class StorageScanServiceTests: XCTestCase {
    func testServiceEmitsProgressAndACompletedInventoryResult() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let auditStore = AuditStore(fileURL: root.appendingPathComponent("audit.jsonl"))
        let snapshotStore = StorageSnapshotStore(fileURL: root.appendingPathComponent("snapshots.json"))
        let service = LocalStorageScanService(
            auditRecorder: auditStore,
            snapshotService: StorageSnapshotService(store: snapshotStore),
            discoverApplications: { _ in [] },
            observeInventory: { _, findings, recoveryItems, _ in
                StorageInventory.capture(findings: findings, recoveryItems: recoveryItems)
            }
        )
        let request = StorageScanRequest(
            home: root,
            rules: [],
            recoveryItems: [],
            totalBytes: 1_000,
            availableBytes: 500
        )

        var reportedProgress = false
        var result: StorageScanResult?
        for await event in service.events(for: request) {
            switch event {
            case StorageScanEvent.progress(_):
                reportedProgress = true
            case let StorageScanEvent.completed(completed):
                result = completed
            }
        }

        XCTAssertTrue(reportedProgress)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.findings, [])
        XCTAssertEqual(result?.inventory.entries, [])
        XCTAssertEqual(result?.snapshotReport.current?.totalBytes, 1_000)
        XCTAssertEqual(auditStore.records().first?.kind, .scan)
    }

    func testServiceAddsPossibleOrphansAsReviewRequiredFindings() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let orphan = root.appendingPathComponent("Library/Caches/com.example.legacy/cache.bin")
        try FileManager.default.createDirectory(at: orphan.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 128).write(to: orphan)

        let auditStore = AuditStore(fileURL: root.appendingPathComponent("audit.jsonl"))
        let service = LocalStorageScanService(
            auditRecorder: auditStore,
            discoverApplications: { _ in [] },
            observeInventory: { _, findings, recoveryItems, _ in
                StorageInventory.capture(findings: findings, recoveryItems: recoveryItems)
            }
        )
        let request = StorageScanRequest(home: root, rules: [], recoveryItems: [], totalBytes: 1_000, availableBytes: 500)

        var result: StorageScanResult?
        for await event in service.events(for: request) {
            if case let .completed(completed) = event {
                result = completed
            }
        }

        let finding = try XCTUnwrap(result?.findings.first)
        XCTAssertEqual(finding.path, orphan.deletingLastPathComponent().path)
        XCTAssertEqual(finding.risk, .reviewRequired)
        XCTAssertEqual(finding.supportedAction, .cleanup)
        XCTAssertEqual(finding.confidence, .needsUserReview)
    }
}
