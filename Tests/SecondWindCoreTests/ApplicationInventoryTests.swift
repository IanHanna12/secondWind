import Foundation
import XCTest
@testable import SecondWindCore
@testable import SecondWindPlatform

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
        let inventory = ApplicationInventory(home: home)
        let preview = inventory.removalPreview(for: app)

        XCTAssertEqual(preview.applicationBytes, 12)
        XCTAssertEqual(preview.exactRemnants.count, 1)
        XCTAssertEqual(preview.exactRemnantBytes, 8)
        XCTAssertEqual(preview.protectedRemnants.count, 1)
        XCTAssertEqual(preview.removableBytes, 20)

        let findings = inventory.uninstallFindings(for: app)
        XCTAssertEqual(findings.filter { $0.supportedAction == .uninstall }.count, 2)
        XCTAssertEqual(findings.first { $0.path == nameBasedSupport.deletingLastPathComponent().path }?.risk, .protected)
        XCTAssertTrue(findings.allSatisfy { $0.category == .applications })
    }

    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)
    }
}
