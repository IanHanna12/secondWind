import Foundation
import SecondWindCore

/// The rule-driven discovery step for cleanup findings.
public struct CleanupScanner: Scanning {
    public let home: URL
    private let fileSystem: any FileSystem
    private let rules: [BuiltInRule]
    public init(home: URL, fileSystem: any FileSystem, rules: [BuiltInRule] = BuiltInRules.all) {
        self.home = home.standardizedFileURL
        self.fileSystem = fileSystem
        self.rules = rules
    }
    public func scan() -> [Finding] {
        scan(progress: { _ in true }).findings
    }

    public func scan(progress: @Sendable (OperationProgress) -> Bool) -> ScanOutcome {
        let totalUnits = rules.count + 3
        var findings: [Finding] = []

        for (index, rule) in rules.enumerated() {
            guard progress(.init(completedUnits: index, totalUnits: totalUnits, title: rule.title)) else {
                return .cancelled
            }
            let url = home.appendingPathComponent(rule.relativePath).standardizedFileURL
            guard fileSystem.exists(url) else { continue }
            findings += findingsForRule(rule, at: url)
        }

        guard progress(.init(completedUnits: rules.count, totalUnits: totalUnits, title: "Downloads")) else {
            return .cancelled
        }
        findings += reviewRequiredFileFindings(in: home.appendingPathComponent("Downloads"))

        guard progress(.init(completedUnits: rules.count + 1, totalUnits: totalUnits, title: "Desktop")) else {
            return .cancelled
        }
        findings += reviewRequiredFileFindings(in: home.appendingPathComponent("Desktop"))

        _ = progress(.init(completedUnits: rules.count + 2, totalUnits: totalUnits, title: "Building known storage inventory"))
        return .completed(findings.filter { $0.byteSize > 0 }.sorted { $0.byteSize > $1.byteSize })
    }

    private func findingsForRule(_ rule: BuiltInRule, at root: URL) -> [Finding] {
        let targets: [URL]
        switch rule.findingScope {
        case .root:
            targets = [root]
        case .immediateChildren:
            let children = fileSystem.directChildren(in: root).filter(fileSystem.exists)
            targets = children.isEmpty ? [root] : children
        }

        return targets.map { target in
            let isRoot = target == root
            let title = isRoot
                ? rule.title
                : "\(rule.title): \(LocalPathDisplay.name(for: target))"
            let explanation = isRoot
                ? rule.explanation
                : "\(rule.explanation) Shown separately so its size and path can be reviewed independently."
            return Finding(
                ruleID: rule.id,
                ruleVersion: rule.version,
                title: title,
                path: target.path,
                byteSize: fileSystem.allocatedSize(at: target),
                category: rule.category,
                origin: "Built-in rule \(rule.id) v\(rule.version)",
                explanation: explanation,
                risk: rule.risk,
                supportedAction: rule.action,
                confidence: rule.confidence
            )
        }
    }

    private func reviewRequiredFileFindings(in root: URL) -> [Finding] {
        let installerExtensions = Set(["dmg", "pkg", "iso", "zip"])
        return fileSystem.regularFiles(in: root, maximumDepth: 4).compactMap { url in
            let size = fileSystem.allocatedSize(at: url); let installer = installerExtensions.contains(url.pathExtension.lowercased())
            guard size >= (installer ? 50 : 500) * 1_024 * 1_024 else { return nil }
            return Finding(ruleID: installer ? "downloaded-installer" : "large-personal-file", ruleVersion: BuiltInRules.version, title: installer ? "Installer: \(url.lastPathComponent)" : url.lastPathComponent, path: url.path, byteSize: size, category: installer ? .installers : .largeFiles, origin: "Built-in user-file rule v\(BuiltInRules.version)", explanation: installer ? "A downloaded installer that may no longer be needed after successful installation." : "A large personal file whose content is unknown to SecondWind.", risk: .reviewRequired, supportedAction: .cleanup, confidence: .needsUserReview)
        }
    }
}

public enum ScanOutcome: Sendable {
    case completed([Finding])
    case cancelled

    public var findings: [Finding] {
        if case let .completed(findings) = self { return findings }
        return []
    }
}
