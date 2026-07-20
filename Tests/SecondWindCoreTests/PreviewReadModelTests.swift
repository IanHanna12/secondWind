import XCTest
@testable import SecondWindApplication
@testable import SecondWindCore
@testable import SecondWindPersistence

final class PreviewReadModelTests: XCTestCase {
    func testDeltaDashboardHighlightsLargestGrowthWithoutRecalculatingChanges() {
        let report = StorageSnapshotReport(
            current: nil,
            previous: StorageSnapshot(totalBytes: 100, availableBytes: 20, entries: []),
            history: [],
            changes: [
                .init(key: "largest", title: "Largest entry", category: "Caches", kind: .grew, byteChange: 200, currentBytes: 300, risk: .safe, explanation: "test", isActionable: true),
                .init(key: "smaller", title: "Smaller entry", category: "Logs", kind: .grew, byteChange: 100, currentBytes: 200, risk: .safe, explanation: "test", isActionable: true)
            ]
        )

        let dashboard = StorageDeltaDashboardBuilder().build(report: report)

        XCTAssertTrue(dashboard.hasComparison)
        XCTAssertEqual(dashboard.largestEntryGrowth?.key, "largest")
        XCTAssertEqual(dashboard.entryChanges.map(\.key), ["largest", "smaller"])
    }

    func testScanHistoryComparesEachSnapshotWithTheOneBeforeIt() {
        let first = snapshot(date: .distantPast, available: 400, entrySize: 100)
        let second = snapshot(date: .distantPast.addingTimeInterval(60), available: 500, entrySize: 250)

        let history = ScanHistoryBuilder().build(snapshots: [first, second])

        XCTAssertEqual(history.map(\.snapshot.id), [second.id, first.id])
        XCTAssertEqual(history[0].observedBytesChange, 150)
        XCTAssertEqual(history[0].availableSpaceChange, 100)
        XCTAssertNil(history[1].observedBytesChange)
    }

    func testRecoveryTimelineGroupsRecoveryAndActivityByDayButExcludesScans() {
        let day = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let recovery = RecoveryItem(id: UUID(), planID: UUID(), originalPath: "/tmp/item", recoveryPath: "/tmp/recovery/item", createdAt: day, byteSize: 1)
        let cleanup = AuditRecord(timestamp: day.addingTimeInterval(10), kind: .executionFinished, ruleVersions: [], paths: [], bytes: 1, result: "success")
        let scan = AuditRecord(timestamp: day.addingTimeInterval(20), kind: .scan, ruleVersions: [], paths: [], bytes: 1, result: "scan")

        let timeline = RecoveryTimelineBuilder().build(recoveryItems: [recovery], auditRecords: [cleanup, scan])

        XCTAssertEqual(timeline.count, 1)
        XCTAssertEqual(timeline[0].events.count, 2)
        XCTAssertEqual(timeline[0].events.map(\.id), ["audit|\(cleanup.id.uuidString)", "recovery|\(recovery.id.uuidString)"])
    }

    private func snapshot(date: Date, available: Int64, entrySize: Int64) -> StorageSnapshot {
        StorageSnapshot(
            capturedAt: date,
            totalBytes: 1_000,
            availableBytes: available,
            entries: [
                .init(key: "fixture", title: "Fixture", category: "Caches", byteSize: entrySize, risk: .safe, explanation: "test", isActionable: true)
            ]
        )
    }
}
