import XCTest
@testable import SecondWindApplication
@testable import SecondWindCore
@testable import SecondWindPersistence

final class StorageExplainabilityTests: XCTestCase {
    func testExplanationUsesTheExistingInventoryFactsForAnEligibleEntry() {
        let entry = StorageInventoryEntry(
            Finding(
                ruleID: "xcode-derived-data",
                ruleVersion: 2,
                title: "Derived Data",
                path: "/Users/test/Library/Developer/Xcode/DerivedData/Project",
                byteSize: 500_000_000,
                category: .developer,
                origin: "Built-in rule xcode-derived-data v2",
                explanation: "Xcode build artifacts are recreated on demand.",
                risk: .safe,
                supportedAction: .cleanup,
                confidence: .exact
            )
        )

        let explanation = DefaultStorageExplanationProvider().explain(entry)

        XCTAssertTrue(explanation.canEnterCleanupPlan)
        XCTAssertTrue(explanation.cleanupReasons.contains { $0.contains("xcode-derived-data v2") })
        XCTAssertTrue(explanation.cleanupReasons.contains { $0.contains("local Recovery") })
        XCTAssertTrue(explanation.facts.contains { $0.title == "Observed by" })
        XCTAssertTrue(explanation.facts.contains { $0.title == "Discovery confidence" && $0.value == "High" })
        XCTAssertEqual(explanation.journey.map(\.title), ["Observed", "Matched rule", "Storage Inventory", "Cleanup review", "Recovery"])
    }

    func testExplanationMakesAProtectedEntryAndItsReasonVisible() {
        let entry = StorageInventoryEntry(
            key: "storage|local|/Users/test/Library/Application Support",
            title: "Application Support",
            path: "/Users/test/Library/Application Support",
            category: .otherSystemData,
            byteSize: 1,
            origin: "Known personal folder",
            explanation: "Contains user-created application data.",
            risk: .protected,
            isActionable: false,
            provider: "Personal folders",
            discoveryConfidence: .high
        )

        let explanation = DefaultStorageExplanationProvider().explain(entry)

        XCTAssertFalse(explanation.canEnterCleanupPlan)
        XCTAssertTrue(explanation.cleanupReasons.isEmpty)
        XCTAssertTrue(explanation.protectionReasons.contains("Contains user-created application data."))
        XCTAssertTrue(explanation.journey.contains { $0.title == "Protected" })
    }

    func testSnapshotRetainsExplanationMetadata() {
        let entry = StorageInventoryEntry(
            Finding(
                ruleID: "npm-cache",
                ruleVersion: 2,
                title: "npm cache",
                path: "/Users/test/.npm/_cacache",
                byteSize: 5,
                category: .packageManagers,
                origin: "Built-in rule npm-cache v2",
                explanation: "npm can recreate downloaded package cache data.",
                risk: .safe,
                supportedAction: .cleanup,
                confidence: .exact
            )
        )
        let snapshot = StorageSnapshotService(store: StorageSnapshotStore(fileURL: temporaryURL())).capture(
            inventory: StorageInventory(entries: [entry]),
            totalBytes: 10,
            availableBytes: 5
        )

        let storedEntry = try! XCTUnwrap(snapshot.entries.first)
        XCTAssertEqual(storedEntry.ruleID, "npm-cache")
        XCTAssertEqual(storedEntry.ruleVersion, 2)
        XCTAssertEqual(storedEntry.provider, "Built-in rule npm-cache v2")
        XCTAssertEqual(storedEntry.discoveryConfidence, .high)
        XCTAssertEqual(storedEntry.supportedAction, .cleanup)
    }

    func testRecommendationCarriesObservableReasons() {
        let entry = StorageInventoryEntry(
            Finding(
                ruleID: "xcode-derived-data",
                ruleVersion: 2,
                title: "Derived Data",
                path: "/Users/test/Library/Developer/Xcode/DerivedData/Project",
                byteSize: 800 * 1_024 * 1_024,
                category: .developer,
                origin: "Built-in rule xcode-derived-data v2",
                explanation: "Xcode build artifacts are recreated on demand.",
                risk: .safe,
                supportedAction: .cleanup,
                confidence: .exact
            )
        )

        let recommendation = StorageRecommendationEngine()
            .recommendations(for: StorageInventory(entries: [entry]))
            .first

        XCTAssertTrue(recommendation?.reasons.contains { $0.contains("Developer Storage") } == true)
        XCTAssertTrue(recommendation?.reasons.contains { $0.contains("Recovery") } == true)
    }

    func testSnapshotDeltaRetainsProviderAndRuleFacts() {
        let date = Date(timeIntervalSinceReferenceDate: 1_000)
        let entry = StorageSnapshotEntry(
            key: "storage|local|/Users/test/.npm/_cacache",
            title: "npm cache",
            path: "/Users/test/.npm/_cacache",
            category: "Developer Storage",
            byteSize: 20 * 1_024 * 1_024,
            origin: "Built-in rule npm-cache v2",
            risk: .safe,
            explanation: "npm can recreate downloaded package cache data.",
            isActionable: true,
            ruleID: "npm-cache",
            ruleVersion: 2,
            provider: "Rules",
            discoveryConfidence: .high,
            supportedAction: .cleanup
        )
        let previous = StorageSnapshot(capturedAt: date, totalBytes: 100, availableBytes: 50, entries: [entry])
        let current = StorageSnapshot(
            capturedAt: date.addingTimeInterval(60),
            totalBytes: 100,
            availableBytes: 40,
            entries: [StorageSnapshotEntry(
                key: entry.key,
                title: entry.title,
                path: entry.path,
                category: entry.category,
                byteSize: 25 * 1_024 * 1_024,
                origin: entry.origin,
                risk: entry.risk,
                explanation: entry.explanation,
                isActionable: entry.isActionable,
                ruleID: entry.ruleID,
                ruleVersion: entry.ruleVersion,
                provider: entry.provider,
                discoveryConfidence: entry.discoveryConfidence,
                supportedAction: entry.supportedAction
            )]
        )

        let report = StorageSnapshotService(store: StorageSnapshotStore(fileURL: temporaryURL()))
            .report(for: current, history: [previous, current])
        let change = report.changes.first

        XCTAssertEqual(change?.provider, "Rules")
        XCTAssertEqual(change?.ruleID, "npm-cache")
        XCTAssertEqual(change?.ruleVersion, 2)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("snapshots.json")
    }
}
