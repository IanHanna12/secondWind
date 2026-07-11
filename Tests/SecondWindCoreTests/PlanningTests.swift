import Foundation
import XCTest
@testable import SecondWindCore
@testable import SecondWindApplication
@testable import SecondWindInfrastructure

final class PlanningTests: XCTestCase {
    func testLegacyRecoveryDestinationDecodesAsRecovery() throws {
        let destination = try JSONDecoder().decode(PlanDestination.self, from: Data("\"quarantine\"".utf8))
        XCTAssertEqual(destination, .recovery)
    }

    func testEveryExecutableBundledRuleCanBePlannedForBothFinalDestinations() throws {
        let home = URL(fileURLWithPath: "/fixture-home")
        let findings = BuiltInRules.all
            .filter { $0.action == .cleanup && $0.risk.isExecutable }
            .map { rule in
                Finding(
                    ruleID: rule.id,
                    ruleVersion: rule.version,
                    title: rule.title,
                    path: home.appendingPathComponent(rule.relativePath).path,
                    byteSize: 1,
                    origin: "test",
                    explanation: rule.explanation,
                    risk: rule.risk,
                    supportedAction: rule.action,
                    confidence: rule.confidence
                )
            }

        for destination in [PlanDestination.recovery, .finderTrash] {
            let plan = try PlanBuilder(home: home).makePlan(
                findings: findings,
                selectedIDs: Set(findings.map(\.id)),
                destination: destination
            )
            XCTAssertEqual(Set(plan.actions.map(\.findingID)), Set(findings.map(\.id)))
            XCTAssertEqual(plan.destination, destination)
        }
    }

    func testReviewedApplicationCanMoveToFinderTrash() throws {
        let home = URL(fileURLWithPath: "/fixture-home")
        let app = Finding(
            ruleID: "application-inventory",
            ruleVersion: 1,
            title: "Application: Example",
            path: "/Applications/Example.app",
            byteSize: 1,
            origin: "test",
            explanation: "test",
            risk: .reviewRequired,
            supportedAction: .uninstall,
            confidence: .exact
        )

        let plan = try PlanBuilder(home: home).makePlan(
            findings: [app],
            selectedIDs: [app.id],
            destination: .finderTrash
        )

        XCTAssertEqual(plan.actions.map(\.sourcePath), [app.path])
    }

    func testPartialFailureReportsCompletedAndFailedPathsInAudit() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }

        let home = root.appendingPathComponent("home")
        let first = home.appendingPathComponent("Downloads/first.dmg")
        let second = home.appendingPathComponent("Downloads/second.dmg")
        try FileManager.default.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)

        let findings = [makeFinding(first), makeFinding(second)]
        let plan = try PlanBuilder(home: home).makePlan(
            findings: findings,
            selectedIDs: Set(findings.map(\.id)),
            destination: .finderTrash
        ).confirmed()
        let audit = AuditStore(url: root.appendingPathComponent("audit.jsonl"))
        let executor = PlanExecutor(
            planBuilder: PlanBuilder(home: home),
            recoveryRepository: RecoveryStore(root: root.appendingPathComponent("recovery")),
            trashMover: FailOnSecondTrash(),
            auditRecorder: audit
        )

        XCTAssertThrowsError(try executor.execute(plan)) { error in
            guard case let PlanExecutionError.actionFailed(completed, failed, _) = error else {
                return XCTFail("Expected a partial-execution error, got \(error)")
            }
            XCTAssertEqual(completed, [first.path])
            XCTAssertEqual(failed, second.path)
        }

        let failure = try XCTUnwrap(audit.records().first { $0.kind == .failure })
        XCTAssertEqual(failure.paths, [first.path, second.path])
        XCTAssertEqual(failure.bytes, findings[0].byteSize)
    }

    private func makeFinding(_ url: URL) -> Finding {
        Finding(ruleID: "fixture", ruleVersion: 1, title: url.lastPathComponent, path: url.path, byteSize: 5, origin: "test", explanation: "test", risk: .safe, supportedAction: .cleanup, confidence: .exact)
    }
}

private struct FailOnSecondTrash: TrashMoving {
    private static let lock = NSLock()
    private static var calls = 0

    init() {
        Self.lock.lock()
        Self.calls = 0
        Self.lock.unlock()
    }

    func moveToTrash(_ url: URL) throws {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        Self.calls += 1
        if Self.calls == 2 { throw CocoaError(.fileWriteUnknown) }
    }
}
