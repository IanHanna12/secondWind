import Foundation
import XCTest
@testable import SecondWindCore
@testable import SecondWindPersistence

final class StorageSnapshotTests: XCTestCase {
    func testReportExplainsGrowthAndNewlyObservedStorage() {
        let service = StorageSnapshotService(store: StorageSnapshotStore(fileURL: temporaryURL()))
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let previous = StorageSnapshot(
            capturedAt: date,
            totalBytes: 100_000_000,
            availableBytes: 70_000_000,
            entries: [entry(key: "derived", title: "Derived Data", bytes: 10_000_000)]
        )
        let current = StorageSnapshot(
            capturedAt: date.addingTimeInterval(60),
            totalBytes: 100_000_000,
            availableBytes: 61_000_000,
            entries: [
                entry(key: "derived", title: "Derived Data", bytes: 16_000_000),
                entry(key: "installer", title: "Installer", bytes: 3_000_000)
            ]
        )

        let report = service.report(for: current, history: [previous, current])

        XCTAssertEqual(report.availableSpaceChange, -9_000_000)
        XCTAssertEqual(report.changes.first { $0.key == "derived" }?.kind, .grew)
        XCTAssertEqual(report.changes.first { $0.key == "derived" }?.byteChange, 6_000_000)
        XCTAssertEqual(report.changes.first { $0.key == "installer" }?.kind, .newlyObserved)
    }

    func testSnapshotsPersistAndIdenticalRapidRefreshDoesNotCreateFalseHistory() throws {
        let url = temporaryURL()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = StorageSnapshotStore(fileURL: url)
        let snapshot = StorageSnapshot(
            capturedAt: Date(), totalBytes: 100, availableBytes: 50,
            entries: [entry(key: "logs", title: "Logs", bytes: 10)]
        )

        XCTAssertEqual(try store.append(snapshot).count, 1)
        XCTAssertEqual(try store.append(snapshot).count, 1)
        XCTAssertEqual(store.snapshots().first?.entries.first?.title, "Logs")
    }

    private func entry(key: String, title: String, bytes: Int64) -> StorageSnapshotEntry {
        StorageSnapshotEntry(key: key, title: title, category: "Developer", byteSize: bytes, risk: .safe, explanation: "Recreated on demand.", isActionable: true)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("snapshots.json")
    }
}
