import Foundation
import XCTest
@testable import SecondWindCore
@testable import SecondWindMacOS

final class ApplicationInventoryTests: XCTestCase {
    func testRemovalPreviewSeparatesExactAndNameBasedSupportPaths() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home")
        let appURL = root.appendingPathComponent("Applications/Example.app")
        let exactSupport = home.appendingPathComponent("Library/Application Support/com.example.app/data.bin")
        let nameBasedSupport = home.appendingPathComponent("Library/Application Support/Example/data.bin")
        try write(Data(repeating: 1, count: 12), to: appURL.appendingPathComponent("Contents/MacOS/Example"))
        try write(Data(repeating: 2, count: 8), to: exactSupport)
        try write(Data(repeating: 3, count: 5), to: nameBasedSupport)

        let app = InstalledApplication(url: appURL, bundleIdentifier: "com.example.app", displayName: "Example")
        let inventory = InstalledApplicationInventory(home: home)
        let preview = inventory.removalPreview(for: app)

        XCTAssertEqual(preview.applicationBytes, 12)
        XCTAssertEqual(preview.exactRemnants.count, 1)
        XCTAssertEqual(preview.exactRemnantBytes, 8)
        XCTAssertEqual(preview.exactRemnants.first?.kind, .applicationSupport)
        XCTAssertEqual(preview.protectedRemnants.count, 1)
        XCTAssertEqual(preview.protectedRemnants.first?.kind, .nameMatch)
        XCTAssertEqual(preview.removableBytes, 20)

        let findings = inventory.uninstallFindings(for: app)
        XCTAssertEqual(findings.filter { $0.supportedAction == .uninstall }.count, 2)
        XCTAssertEqual(findings.first { $0.path == nameBasedSupport.deletingLastPathComponent().path }?.risk, .protected)
        XCTAssertTrue(findings.allSatisfy { $0.category == .applications })
    }

    func testAssociationResolverExplainsKnownPathsWithoutChangingEligibility() {
        let home = URL(fileURLWithPath: "/Users/test")
        let app = InstalledApplication(
            url: URL(fileURLWithPath: "/Applications/Example.app"),
            bundleIdentifier: "com.example.app",
            displayName: "Example"
        )
        let cache = StorageInventoryEntry(
            key: "finding|cache|/Users/test/Library/Caches/com.example.app",
            title: "Example cache",
            path: "/Users/test/Library/Caches/com.example.app",
            category: .caches,
            byteSize: 10_000_000,
            origin: "Built-in cache rule",
            explanation: "Recreated on demand.",
            risk: .safe,
            isActionable: true
        )

        let resolved = ApplicationAssociationResolver(home: home).resolve(
            inventory: StorageInventory(entries: [cache]),
            applications: [app]
        )
        let entry = resolved.entries.first
        let association = entry?.applicationAssociations.first
        let projection = ApplicationInventory(storageInventory: resolved, applications: [app])

        XCTAssertEqual(association?.relationship, .cache)
        XCTAssertEqual(association?.evidence, .knownPath)
        XCTAssertTrue(entry?.isActionable ?? false)
        XCTAssertEqual(projection.profiles.first?.totalKnownBytes, 10_000_000)
        XCTAssertEqual(projection.profiles.first?.cleanupCandidateBytes, 10_000_000)
    }

    func testAssociationResolverMarksIdentifierPathWithoutInstalledAppAsPossibleOrphan() {
        let home = URL(fileURLWithPath: "/Users/test")
        let orphanCache = StorageInventoryEntry(
            key: "observed|orphan",
            title: "Unknown cache",
            path: "/Users/test/Library/Caches/com.example.legacy",
            category: .caches,
            byteSize: 10_000_000,
            origin: "Known application storage path",
            explanation: "Observed locally.",
            risk: .protected,
            isActionable: false
        )

        let resolved = ApplicationAssociationResolver(home: home).resolve(
            inventory: StorageInventory(entries: [orphanCache]),
            applications: []
        )
        let projection = ApplicationInventory(storageInventory: resolved, applications: [])

        XCTAssertEqual(projection.possibleOrphans.first?.identity.bundleIdentifier, "com.example.legacy")
        XCTAssertFalse(projection.possibleOrphans.first?.entries.first?.storage.isActionable ?? true)
    }

    func testObserverFindsIdentifierBasedOrphanAsReviewRequiredStorage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let orphan = root.appendingPathComponent("Library/Caches/com.example.legacy/cache.bin")
        try write(Data(repeating: 4, count: 128), to: orphan)

        let entries = ApplicationStorageObserver(home: root).entries(for: [])
        let observed = try XCTUnwrap(entries.first { $0.path == orphan.deletingLastPathComponent().path })

        XCTAssertEqual(observed.risk, .reviewRequired)
        XCTAssertTrue(observed.isActionable)

        let findings = ApplicationStorageObserver(home: root).orphanCleanupFindings(for: [])
        let finding = try XCTUnwrap(findings.first { $0.path == observed.path })
        XCTAssertEqual(finding.risk, .reviewRequired)
        XCTAssertEqual(finding.supportedAction, .cleanup)
        XCTAssertEqual(finding.confidence, .needsUserReview)

        let inventory = ApplicationAssociationResolver(home: root).resolve(
            inventory: StorageInventory(entries: entries),
            applications: []
        )
        XCTAssertEqual(inventory.entries.first?.applicationAssociations.first?.evidence, .possibleOrphan)
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
