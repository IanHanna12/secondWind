import Foundation
import SecondWindCore

public struct RuleEngine: Sendable {
    public let home: URL
    private let fileSystem: any FileSystem
    public init(home: URL, fileSystem: any FileSystem) {
        self.home = home.standardizedFileURL
        self.fileSystem = fileSystem
    }
    public func scan() -> [Finding] {
        scan(progress: { _ in true }).findings
    }

    public func scan(progress: @Sendable (ScanProgress) -> Bool) -> ScanOutcome {
        let rules = BuiltInRules.all
        let totalUnits = rules.count + 2
        var findings: [Finding] = []

        for (index, rule) in rules.enumerated() {
            guard progress(.init(completedUnits: index, totalUnits: totalUnits, currentTitle: rule.title)) else {
                return .cancelled
            }
            let url = home.appendingPathComponent(rule.relativePath).standardizedFileURL
            guard fileSystem.exists(url) else { continue }
            findings.append(Finding(ruleID: rule.id, ruleVersion: rule.version, title: rule.title, path: url.path, byteSize: fileSystem.fileSize(at: url), category: rule.category, origin: "Built-in rule \(rule.id) v\(rule.version)", explanation: rule.explanation, risk: rule.risk, supportedAction: rule.action, confidence: rule.confidence))
        }

        guard progress(.init(completedUnits: rules.count, totalUnits: totalUnits, currentTitle: "Downloads")) else {
            return .cancelled
        }
        findings += reviewRequiredFileFindings(in: home.appendingPathComponent("Downloads"))

        guard progress(.init(completedUnits: rules.count + 1, totalUnits: totalUnits, currentTitle: "Desktop")) else {
            return .cancelled
        }
        findings += reviewRequiredFileFindings(in: home.appendingPathComponent("Desktop"))

        _ = progress(.init(completedUnits: totalUnits, totalUnits: totalUnits, currentTitle: "Finishing scan"))
        return .completed(findings.filter { $0.byteSize > 0 }.sorted { $0.byteSize > $1.byteSize })
    }

    private func reviewRequiredFileFindings(in root: URL) -> [Finding] {
        let installerExtensions = Set(["dmg", "pkg", "iso", "zip"])
        return fileSystem.regularFiles(in: root, maximumDepth: 4).compactMap { url in
            let size = fileSystem.fileSize(at: url); let installer = installerExtensions.contains(url.pathExtension.lowercased())
            guard size >= (installer ? 50 : 500) * 1_024 * 1_024 else { return nil }
            return Finding(ruleID: installer ? "downloaded-installer" : "large-personal-file", ruleVersion: BuiltInRules.version, title: installer ? "Installer: \(url.lastPathComponent)" : url.lastPathComponent, path: url.path, byteSize: size, category: installer ? .installers : .largeFiles, origin: "Built-in user-file rule v\(BuiltInRules.version)", explanation: installer ? "A downloaded installer that may no longer be needed after successful installation." : "A large personal file whose content is unknown to SecondWind.", risk: .reviewRequired, supportedAction: .cleanup, confidence: .needsUserReview)
        }
    }
}

public struct ScanProgress: Sendable {
    public let completedUnits: Int
    public let totalUnits: Int
    public let currentTitle: String
    public var fraction: Double { Double(completedUnits) / Double(max(1, totalUnits)) }

    public init(completedUnits: Int, totalUnits: Int, currentTitle: String) {
        self.completedUnits = completedUnits
        self.totalUnits = totalUnits
        self.currentTitle = currentTitle
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
