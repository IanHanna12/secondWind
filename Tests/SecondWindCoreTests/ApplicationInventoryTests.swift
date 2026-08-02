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
        let discoverer = InstalledApplicationDiscoverer(home: home)
        let preview = discoverer.removalPreview(for: app)
        let fileSystem = LocalFileSystem()
        let applicationBytes = fileSystem.allocatedSize(at: appURL)
        let exactSupportBytes = fileSystem.allocatedSize(at: exactSupport.deletingLastPathComponent())
        let protectedSupportBytes = fileSystem.allocatedSize(at: nameBasedSupport.deletingLastPathComponent())

        XCTAssertEqual(preview.applicationBytes, applicationBytes)
        XCTAssertEqual(preview.exactRemnants.count, 1)
        XCTAssertEqual(preview.exactRemnantBytes, exactSupportBytes)
        XCTAssertEqual(preview.exactRemnants.first?.kind, .applicationSupport)
        XCTAssertEqual(preview.protectedRemnants.count, 1)
        XCTAssertEqual(preview.protectedRemnants.first?.byteSize, protectedSupportBytes)
        XCTAssertEqual(preview.protectedRemnants.first?.kind, .nameMatch)
        XCTAssertEqual(preview.removableBytes, applicationBytes + exactSupportBytes)

        let findings = discoverer.uninstallFindings(for: app)
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

    func testDiscoveryFindsIdentifierBasedOrphanAsReviewRequiredStorage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let orphan = root.appendingPathComponent("Library/Caches/com.example.legacy/cache.bin")
        try write(Data(repeating: 4, count: 128), to: orphan)

        let entries = ApplicationStorageDiscovery(home: root).inventoryEntries(for: [])
        let observed = try XCTUnwrap(entries.first { $0.path == orphan.deletingLastPathComponent().path })

        XCTAssertEqual(observed.risk, .reviewRequired)
        XCTAssertTrue(observed.isActionable)

        let findings = ApplicationStorageDiscovery(home: root).orphanCleanupFindings(for: [])
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

    func testDiscoveryProtectsAppleAndDataBearingPossibleOrphans() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let appleCache = root.appendingPathComponent("Library/Caches/com.apple.example/cache.bin")
        let thirdPartyContainer = root.appendingPathComponent("Library/Containers/com.example.legacy/data.bin")
        try write(Data(repeating: 1, count: 128), to: appleCache)
        try write(Data(repeating: 2, count: 128), to: thirdPartyContainer)

        let discovery = ApplicationStorageDiscovery(home: root)
        let entries = discovery.inventoryEntries(for: [])
        let appleEntry = try XCTUnwrap(entries.first { $0.path == appleCache.deletingLastPathComponent().path })
        let containerEntry = try XCTUnwrap(entries.first { $0.path == thirdPartyContainer.deletingLastPathComponent().path })

        XCTAssertEqual(appleEntry.risk, .protected)
        XCTAssertFalse(appleEntry.isActionable)
        XCTAssertEqual(containerEntry.risk, .protected)
        XCTAssertFalse(containerEntry.isActionable)

        let cleanupPaths = Set(discovery.orphanCleanupFindings(for: []).map(\.path))
        XCTAssertFalse(cleanupPaths.contains(try XCTUnwrap(appleEntry.path)))
        XCTAssertFalse(cleanupPaths.contains(try XCTUnwrap(containerEntry.path)))
    }

    func testAllocatedSizeDoesNotUseSparseFileLogicalCapacity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let sparseFile = root.appendingPathComponent("sparse.raw")
        XCTAssertTrue(FileManager.default.createFile(atPath: sparseFile.path, contents: nil))
        let handle = try FileHandle(forWritingTo: sparseFile)
        try handle.truncate(atOffset: 1_000_000_000)
        try handle.close()

        let logicalSize = try XCTUnwrap(
            try sparseFile.resourceValues(forKeys: [.fileSizeKey]).fileSize
        )
        let allocatedSize = LocalFileSystem().allocatedSize(at: sparseFile)

        XCTAssertEqual(logicalSize, 1_000_000_000)
        XCTAssertLessThan(allocatedSize, Int64(logicalSize))
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
