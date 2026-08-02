import Foundation
import XCTest
@testable import SecondWindCore
@testable import SecondWindApplication
@testable import SecondWindPersistence

final class PlanningTests: XCTestCase {
    func testRulePolicyRejectsUnknownBuiltInRuleIdentifiers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RulePolicyStore(url: root.appendingPathComponent("rules.json"))
        let policy = RulePolicy(disabledBuiltInRuleIDs: ["unknown-rule"])

        XCTAssertThrowsError(try store.validate(policy)) { error in
            XCTAssertEqual(error as? RulePolicyError, .unknownBuiltInRule("unknown-rule"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testUnsupportedFutureRulePolicyIsNotOverwritten() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("rules.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let futureDocument = Data("{\"schemaVersion\":999,\"disabledBuiltInRuleIDs\":[],\"userRules\":[]}".utf8)
        try futureDocument.write(to: url)
        let store = RulePolicyStore(url: url)

        XCTAssertThrowsError(try store.apply(.builtInRule(id: BuiltInRules.all[0].id, enabled: false)))
        XCTAssertEqual(try Data(contentsOf: url), futureDocument)
        XCTAssertTrue(store.policy().userRules.isEmpty)
    }

    func testRulePolicyChangesUseTheCurrentStoredPolicy() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RulePolicyStore(url: root.appendingPathComponent("rules.json"))

        let policyWithRule = try store.apply(
            .addUserRule(
                title: "Local cache",
                route: .userCaches,
                explanation: "A locally generated cache."
            )
        )
        let ruleID = try XCTUnwrap(policyWithRule.userRules.first?.id)

        let updatedPolicy = try store.apply(.userRule(id: ruleID, enabled: false))

        XCTAssertEqual(updatedPolicy.userRules.count, 1)
        XCTAssertEqual(updatedPolicy.userRules.first?.id, ruleID)
        XCTAssertEqual(updatedPolicy.userRules.first?.isEnabled, false)
        XCTAssertEqual(try store.load().userRules, updatedPolicy.userRules)
    }

    func testRulePolicyChangeRejectsMissingUserRule() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = RulePolicyStore(url: root.appendingPathComponent("rules.json"))
        let missingRuleID = UUID()

        XCTAssertThrowsError(try store.apply(.userRule(id: missingRuleID, enabled: false))) { error in
            XCTAssertEqual(error as? RulePolicyError, .unknownUserRule(missingRuleID))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

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

    func testReviewedOrphanedApplicationContainerCannotEnterCleanupPlan() throws {
        let home = URL(fileURLWithPath: "/fixture-home")
        let orphan = Finding(
            ruleID: "orphaned-application-storage",
            ruleVersion: 1,
            title: "Possible orphan: com.example.legacy",
            path: home.appendingPathComponent("Library/Containers/com.example.legacy").path,
            byteSize: 1,
            category: .applications,
            origin: "test",
            explanation: "test",
            risk: .reviewRequired,
            supportedAction: .cleanup,
            confidence: .needsUserReview
        )

        XCTAssertThrowsError(try PlanBuilder(home: home).makePlan(
            findings: [orphan],
            selectedIDs: [orphan.id],
            destination: .recovery
        ))
    }

    func testOnlyThirdPartyOrphanCachesAndLogsCanEnterCleanupPlans() throws {
        let home = URL(fileURLWithPath: "/fixture-home")
        let thirdPartyCache = Finding(
            ruleID: "orphaned-application-storage",
            ruleVersion: 1,
            title: "Possible orphan: com.example.legacy",
            path: home.appendingPathComponent("Library/Caches/com.example.legacy").path,
            byteSize: 1,
            category: .caches,
            origin: "test",
            explanation: "test",
            risk: .reviewRequired,
            supportedAction: .cleanup,
            confidence: .needsUserReview
        )
        let appleCache = Finding(
            ruleID: "orphaned-application-storage",
            ruleVersion: 1,
            title: "Possible orphan: com.apple.example",
            path: home.appendingPathComponent("Library/Caches/com.apple.example").path,
            byteSize: 1,
            category: .caches,
            origin: "test",
            explanation: "test",
            risk: .reviewRequired,
            supportedAction: .cleanup,
            confidence: .needsUserReview
        )

        XCTAssertNoThrow(try PlanBuilder(home: home).makePlan(
            findings: [thirdPartyCache],
            selectedIDs: [thirdPartyCache.id],
            destination: .recovery
        ))
        XCTAssertThrowsError(try PlanBuilder(home: home).makePlan(
            findings: [appleCache],
            selectedIDs: [appleCache.id],
            destination: .recovery
        ))
    }

    func testPartialFailureRecordsAnOutcomeForEveryActionAndAuditsIt() async throws {
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
        let audit = AuditStore(fileURL: root.appendingPathComponent("audit.jsonl"))
        let executor = PlanExecutor(
            planBuilder: PlanBuilder(home: home),
            recoveryStore: RecoveryStore(root: root.appendingPathComponent("recovery")),
            trashMover: FailOnSecondTrash(),
            auditStore: audit
        )

        let outcome = try await executor.executeWithOutcome(plan)
        XCTAssertEqual(outcome.movedBytes, findings[0].byteSize)
        XCTAssertEqual(outcome.results.map(\.action.sourcePath), [first.path, second.path])
        XCTAssertEqual(outcome.results[0].outcome, .completedNotYetObservable)
        XCTAssertEqual(outcome.results[1].outcome, .failed(reason: CocoaError(.fileWriteUnknown).localizedDescription))

        let failure = try XCTUnwrap(audit.records().first { $0.kind == .failure })
        XCTAssertEqual(failure.paths, [first.path, second.path])
        XCTAssertEqual(failure.bytes, findings[0].byteSize)
        XCTAssertEqual(failure.ruleVersions, ["fixture v1"])
    }

    private func makeFinding(_ url: URL) -> Finding {
        Finding(ruleID: "fixture", ruleVersion: 1, title: url.lastPathComponent, path: url.path, byteSize: 5, origin: "test", explanation: "test", risk: .safe, supportedAction: .cleanup, confidence: .exact)
    }
}

private actor FailOnSecondTrash: TrashMoving {
    private var calls = 0

    func moveToTrash(_ url: URL) async throws {
        calls += 1
        if calls == 2 { throw CocoaError(.fileWriteUnknown) }
    }
}
