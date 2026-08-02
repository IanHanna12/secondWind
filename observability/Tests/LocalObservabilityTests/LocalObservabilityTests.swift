import XCTest
@testable import LocalObservability

final class ObservabilityTests: XCTestCase {
    func testLoopbackConfigurationRejectsEveryOtherAddress() throws {
        XCTAssertThrowsError(try LocalObservabilityConfiguration(address: "0.0.0.0"))
        XCTAssertThrowsError(try LocalObservabilityConfiguration(address: "::1"))
        XCTAssertNoThrow(try LocalObservabilityConfiguration())
    }

    func testPrometheusRenderingUsesOnlyFixedCategoryLabels() {
        let output = DefaultPrometheusMetricsRenderer().render(snapshot: sampleSnapshot())

        XCTAssertTrue(output.contains("secondwind_category_storage_bytes{category=\"developer_storage\"} 4096"))
        XCTAssertTrue(output.contains("secondwind_storage_bytes 4096"))
        XCTAssertTrue(output.contains("secondwind_recovery_entries 0"))
        XCTAssertFalse(output.contains("secondwind_recovery_items"))
        XCTAssertFalse(output.contains("secondwind_provider"))
        XCTAssertFalse(output.contains("/Users/"))
        XCTAssertFalse(output.contains("Example App"))
    }

    func testJSONRenderingDoesNotContainPathsOrRecoveryReferences() throws {
        let data = try DefaultObservabilityJSONRenderer().summary(snapshot: sampleSnapshot())
        let text = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(text.contains("/Users/"))
        XCTAssertFalse(text.contains("recovery-path"))
        XCTAssertTrue(text.contains("\"schemaVersion\":1"))
        XCTAssertTrue(text.contains("developer_storage"))
    }

    func testEveryJSONEndpointDeclaresTheStableSchemaVersion() throws {
        let renderer = DefaultObservabilityJSONRenderer()
        let responses = [
            try renderer.health(snapshot: sampleSnapshot()),
            try renderer.summary(snapshot: sampleSnapshot()),
            try renderer.latestDelta(snapshot: sampleSnapshot())
        ]

        for response in responses {
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: response) as? [String: Any])
            XCTAssertEqual(object["schemaVersion"] as? Int, LocalObservabilitySnapshot.currentSchemaVersion)
        }
    }

    func testSnapshotStoreReplacesTheWholeSnapshot() async {
        let store = LocalObservabilitySnapshotStore(initial: sampleSnapshot())
        var replacement = sampleSnapshot()
        replacement = LocalObservabilitySnapshot(
            generatedAt: replacement.generatedAt.addingTimeInterval(1),
            inventory: .init(observedBytes: 8_192, entryCount: 2, cleanupEligibleEntryCount: 1, protectedEntryCount: 1, categories: []),
            scan: replacement.scan,
            recovery: replacement.recovery,
            cleanup: replacement.cleanup,
            providers: replacement.providers,
            delta: replacement.delta,
            applications: nil
        )

        await store.replace(with: replacement)
        let served = await store.snapshot()
        XCTAssertEqual(served?.inventory.observedBytes, 8_192)
        XCTAssertEqual(served?.inventory.entryCount, 2)
    }

    func testObservabilitySnapshotUsesItsGenerationTimeAsCaptureTime() {
        let snapshot = sampleSnapshot()

        XCTAssertEqual(snapshot.capturedAt, snapshot.generatedAt)
    }

    func testPrometheusSnapshotFileContainsOnlyRenderedAggregateData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("secondwind-observability-\(UUID().uuidString)")
        let url = directory.appendingPathComponent("metrics.prom")
        defer { try? FileManager.default.removeItem(at: directory) }

        try PrometheusSnapshotFile(url: url).replace(with: sampleSnapshot())
        let contents = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(contents.contains("secondwind_snapshot_available 1"))
        XCTAssertTrue(contents.contains("secondwind_storage_bytes 4096"))
        XCTAssertFalse(contents.contains("/Users/"))
        XCTAssertFalse(contents.contains("recovery-path"))
    }

    private func sampleSnapshot() -> LocalObservabilitySnapshot {
        LocalObservabilitySnapshot(
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            inventory: .init(
                observedBytes: 4_096,
                entryCount: 1,
                cleanupEligibleEntryCount: 1,
                protectedEntryCount: 0,
                categories: [.init(category: "developer_storage", observedBytes: 4_096, entryCount: 1, deltaBytes: 512)]
            ),
            scan: .init(lastCompletedAt: Date(timeIntervalSince1970: 1_700_000_000), completedCount: 2, failedCount: 0, cancelledCount: 0),
            recovery: .init(bytes: 0, itemCount: 0, oldestItemAgeSeconds: nil),
            cleanup: .init(executionCount: 1, completedBytes: 1_024, trashBytes: 0, recoveryBytes: 1_024),
            providers: .init(distinctProviderCount: 2, observedEntryCount: 1),
            delta: .init(snapshotAvailable: true, comparedSnapshotAvailable: true, availableStorageDeltaBytes: 512, largestCategoryChanges: [.init(category: "developer_storage", byteChange: 512, currentBytes: 4_096)]),
            applications: nil
        )
    }
}
