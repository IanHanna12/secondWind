import Foundation
import SecondWindCore
import SecondWindApplication
import SecondWindInfrastructure
import SecondWindPlatform

enum VerificationError: Error { case failed(String) }
func check(_ value: @autoclosure () -> Bool, _ message: String) throws { if !value() { throw VerificationError.failed(message) } }

struct FixtureFileSystem: FileSystem {
    let paths: [URL: Int64]
    func exists(_ url: URL) -> Bool { paths[url] != nil }
    func fileSize(at url: URL) -> Int64 { paths[url] ?? 0 }
    func regularFiles(in root: URL, maximumDepth: Int) -> [URL] { [] }
}

func finding(_ path: String, risk: Risk) -> Finding { Finding(ruleID: "fixture", ruleVersion: 1, title: "Fixture", path: path, byteSize: 1, origin: "test", explanation: "test", risk: risk, supportedAction: risk == .protected ? .none : .cleanup, confidence: .exact) }

func verify() throws {
    let home = URL(fileURLWithPath: "/fixture-home")
    let docker = home.appendingPathComponent("Library/Containers/com.docker.docker")
    let logs = home.appendingPathComponent("Library/Logs")
    let findings = RuleEngine(home: home, fileSystem: FixtureFileSystem(paths: [docker: 10, logs: 20])).scan()
    try check(findings.first { $0.ruleID == "user-logs" }?.confidence == .exact, "exact rule match")
    try check(findings.first { $0.ruleID == "docker-data" }?.risk == .protected, "protected Docker")

    let protected = finding(docker.path, risk: .protected)
    do { _ = try PlanBuilder(home: home).makePlan(findings: [protected], selectedIDs: [protected.id], destination: .recovery); throw VerificationError.failed("protected plan was accepted") } catch PlanError.protectedFinding { }
    let safe = finding(home.appendingPathComponent("Library/Logs/a.log").path, risk: .safe)
    let plan = try PlanBuilder(home: home).makePlan(findings: [safe], selectedIDs: [safe.id], destination: .recovery)
    do { try PlanBuilder(home: home).validate(plan); throw VerificationError.failed("unconfirmed plan was accepted") } catch PlanError.planNotConfirmed { }
    try PlanBuilder(home: home).validate(plan.confirmed())
    do { _ = try PlanBuilder(home: home).makePlan(findings: [safe], selectedIDs: [safe.id], destination: .finderTrash); throw VerificationError.failed("Trash accepted logs") } catch PlanError.destinationNotAllowed { }

    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("source/report.txt"); try FileManager.default.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true); try Data("one".utf8).write(to: source)
    let store = RecoveryStore(root: root.appendingPathComponent("recovery")); let item = try store.storeInRecovery(source, planID: UUID()); try Data("existing".utf8).write(to: source)
    let restored = try store.restore(item)
    try check(restored.lastPathComponent.contains("Restored from Recovery"), "descriptive duplicate restore")
    let audit = AuditStore(fileURL: root.appendingPathComponent("audit.jsonl")); try audit.append(.init(kind: .scan, ruleVersions: ["user-logs v1"], paths: ["/tmp/log"], bytes: 1, result: "ok")); try audit.append(.init(kind: .dryRun, ruleVersions: [], paths: [], bytes: 0, result: "ok")); try check(audit.records().count == 2, "append-only audit"); try check(audit.exportMarkdown().contains("dryRun"), "audit markdown export")
}

do { try verify(); print("SecondWindCore verification passed") } catch { fputs("SecondWindCore verification failed: \(error)\n", stderr); exit(1) }
