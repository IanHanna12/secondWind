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

    func testInventoryIsTheSharedSourceForRecoveryAndKnownFindings() {
        let finding = Finding(
            ruleID: "xcode", ruleVersion: 1, title: "Derived Data", path: "/Users/test/Library/Developer/Xcode/DerivedData",
            byteSize: 10_000_000, category: .developer, origin: "Built-in rule xcode v1",
            explanation: "Recreated by Xcode.", risk: .safe, supportedAction: .cleanup, confidence: .exact
        )
        let recovery = RecoveryItem(
            id: UUID(), planID: UUID(), originalPath: "/Users/test/Downloads/archive.zip", recoveryPath: "/private/recovery/archive.zip",
            createdAt: Date(), byteSize: 3_000_000
        )

        let inventory = StorageInventory.capture(findings: [finding], recoveryItems: [recovery])

        XCTAssertEqual(inventory.entries.count, 2)
        XCTAssertEqual(inventory.entries.first { $0.category == StorageCategory.developerStorage }?.title, "Derived Data")
        XCTAssertEqual(inventory.entries.first { $0.category == StorageCategory.recovery }?.risk, .protected)
    }

    func testCategoryChangesAggregateKnownEntries() {
        let service = StorageSnapshotService(store: StorageSnapshotStore(fileURL: temporaryURL()))
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let previous = StorageSnapshot(
            capturedAt: date, totalBytes: 100_000_000, availableBytes: 70_000_000,
            entries: [entry(key: "derived", title: "Derived Data", bytes: 10_000_000, category: "Developer Storage")]
        )
        let current = StorageSnapshot(
            capturedAt: date.addingTimeInterval(60), totalBytes: 100_000_000, availableBytes: 64_000_000,
            entries: [
                entry(key: "derived", title: "Derived Data", bytes: 14_000_000, category: "Developer Storage"),
                entry(key: "npm", title: "npm cache", bytes: 2_000_000, category: "Developer Storage")
            ]
        )

        let report = service.report(for: current, history: [previous, current])

        XCTAssertEqual(report.categorySummaries.first?.category, .developerStorage)
        XCTAssertEqual(report.categorySummaries.first?.byteSize, 16_000_000)
        XCTAssertEqual(report.categoryChanges.first?.category, .developerStorage)
        XCTAssertEqual(report.categoryChanges.first?.byteChange, 6_000_000)
    }

    func testReportMarksMissingKnownStorageAsNoLongerObserved() {
        let service = StorageSnapshotService(store: StorageSnapshotStore(fileURL: temporaryURL()))
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let previous = StorageSnapshot(
            capturedAt: date, totalBytes: 100_000_000, availableBytes: 70_000_000,
            entries: [entry(key: "logs", title: "Diagnostic logs", bytes: 5_000_000, category: "Logs")]
        )
        let current = StorageSnapshot(
            capturedAt: date.addingTimeInterval(60), totalBytes: 100_000_000, availableBytes: 75_000_000, entries: []
        )

        let report = service.report(for: current, history: [previous, current])

        XCTAssertEqual(report.changes.first?.kind, .noLongerObserved)
        XCTAssertEqual(report.changes.first?.byteChange, -5_000_000)
    }

    func testRecommendationsAreDeterministicAndNeverIncludeProtectedEntries() {
        let oldDate = Date(timeIntervalSinceReferenceDate: 1_000)
        let inventory = StorageInventory(entries: [
            StorageInventoryEntry(
                key: "developer", title: "Derived Data", path: "/tmp/derived", category: .developerStorage,
                byteSize: 800 * 1_024 * 1_024, origin: "Built-in rule xcode v2", explanation: "Recreated by Xcode.",
                risk: .safe, isActionable: true
            ),
            StorageInventoryEntry(
                key: "old-download", title: "Old installer", path: "/tmp/installer.pkg", category: .downloads,
                byteSize: 600 * 1_024 * 1_024, origin: "Built-in download rule", explanation: "Needs review.",
                risk: .reviewRequired, isActionable: true, modifiedAt: oldDate
            ),
            StorageInventoryEntry(
                key: "protected", title: "Browser profile", path: "/tmp/profile", category: .otherSystemData,
                byteSize: 900 * 1_024 * 1_024, origin: "Built-in rule", explanation: "Protected.",
                risk: .protected, isActionable: false
            )
        ])

        let recommendations = StorageRecommendationEngine().recommendations(for: inventory, now: oldDate.addingTimeInterval(121 * 24 * 60 * 60))

        XCTAssertEqual(recommendations.map(\.entry.key), ["developer", "old-download"])
        XCTAssertEqual(recommendations.last?.title, "Older large file")
    }

    private func entry(key: String, title: String, bytes: Int64, category: String = "Developer") -> StorageSnapshotEntry {
        StorageSnapshotEntry(key: key, title: title, category: category, byteSize: bytes, risk: .safe, explanation: "Recreated on demand.", isActionable: true)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("snapshots.json")
    }
}
