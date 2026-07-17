import Foundation
import XCTest
@testable import SecondWindCore
@testable import SecondWindApplication

final class CleanupScannerTests: XCTestCase {
    func testRebuildableDeveloperAndPackageCachesAreEligibleForCleanup() {
        let home = URL(fileURLWithPath: "/fixture-home")
        let ruleIDs = [
            "xcode-device-support",
            "core-simulator-caches",
            "gradle-wrapper-cache",
            "yarn-cache",
            "pip-cache",
            "cargo-registry-cache",
            "cocoapods-cache"
        ]
        let paths = Dictionary(
            uniqueKeysWithValues: try! ruleIDs.enumerated().map { index, id in
                let rule = try XCTUnwrap(BuiltInRules.all.first { $0.id == id })
                return (home.appendingPathComponent(rule.relativePath).standardizedFileURL, Int64(index + 1) * 1_024)
            }
        )

        let findings = CleanupScanner(home: home, fileSystem: FixtureFileSystem(paths: paths)).scan()

        XCTAssertEqual(Set(findings.map(\.ruleID)), Set(ruleIDs))
        for finding in findings {
            XCTAssertEqual(finding.risk, .safe)
            XCTAssertEqual(finding.supportedAction, .cleanup)
            XCTAssertEqual(finding.confidence, .exact)
            XCTAssertNotNil(finding.category)
            XCTAssertFalse(finding.explanation.isEmpty)
        }
    }

    func testScanCanBeCancelledBeforeReadingAPath() {
        let home = URL(fileURLWithPath: "/fixture-home")
        let outcome = CleanupScanner(home: home, fileSystem: FixtureFileSystem(paths: [:])).scan { _ in false }

        guard case .cancelled = outcome else {
            return XCTFail("Expected the scan to report cancellation")
        }
    }

    func testGranularRuleCreatesOneFindingPerDirectChild() {
        let home = URL(fileURLWithPath: "/fixture-home")
        let root = home.appendingPathComponent("Library/Caches/Example")
        let firstChild = root.appendingPathComponent("First")
        let secondChild = root.appendingPathComponent("Second")
        let rule = BuiltInRule(
            id: "example-cache",
            version: 2,
            title: "Example cache",
            relativePath: "Library/Caches/Example",
            category: .caches,
            risk: .safe,
            action: .cleanup,
            explanation: "Recreated on demand.",
            findingScope: .immediateChildren
        )
        let fileSystem = FixtureFileSystem(
            paths: [root: 3_000, firstChild: 1_000, secondChild: 2_000],
            children: [root: [firstChild, secondChild]]
        )

        let findings = CleanupScanner(home: home, fileSystem: fileSystem, rules: [rule]).scan()

        XCTAssertEqual(findings.map(\.path), [secondChild.path, firstChild.path])
        XCTAssertEqual(findings.map(\.title), ["Example cache: Second", "Example cache: First"])
        XCTAssertTrue(findings.allSatisfy { $0.explanation.contains("reviewed independently") })
        XCTAssertTrue(findings.allSatisfy { $0.ruleVersion == 2 })
    }

    func testSensitiveDataRemainsProtectedByBundledPolicy() {
        let policy = Dictionary(uniqueKeysWithValues: BuiltInRules.all.map { ($0.id, $0) })

        XCTAssertEqual(policy["docker-data"]?.risk, .protected)
        XCTAssertEqual(policy["docker-data"]?.action, SupportedAction.none)
        XCTAssertEqual(policy["browser-data"]?.risk, .protected)
        XCTAssertEqual(policy["browser-data"]?.action, SupportedAction.none)
        XCTAssertEqual(policy["simulator-devices"]?.risk, .reviewRequired)
        XCTAssertEqual(policy["simulator-devices"]?.confidence, .needsUserReview)
    }
}

private struct FixtureFileSystem: FileSystem {
    let paths: [URL: Int64]
    var children: [URL: [URL]] = [:]

    func exists(_ url: URL) -> Bool { paths[url] != nil }
    func fileSize(at url: URL) -> Int64 { paths[url] ?? 0 }
    func directChildren(in root: URL) -> [URL] { children[root] ?? [] }
    func regularFiles(in root: URL, maximumDepth: Int) -> [URL] { [] }
}
