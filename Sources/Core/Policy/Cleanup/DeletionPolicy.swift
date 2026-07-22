import Foundation

/// Internal safety policy for cleanup execution. User rules can identify
/// candidates, but cannot broaden these deletion boundaries.
public struct DeletionPolicy: Policy {
    public init() {}

    public func permits(_ finding: Finding, destination: PlanDestination, home: URL) -> Bool {
        permits(path: finding.path, action: finding.supportedAction, destination: destination, home: home)
    }

    public func permits(_ action: PlanAction, destination: PlanDestination, home: URL) -> Bool {
        permits(path: action.sourcePath, action: action.action, destination: destination, home: home)
    }

    private func permits(path: String, action: SupportedAction, destination: PlanDestination, home: URL) -> Bool {
        guard destination != .systemTask else { return false }
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path

        if action == .uninstall, isUnderSystemApplications(normalizedPath) {
            return true
        }

        return allowedRelativeRoots(for: action).contains { relativeRoot in
            let root = home.appendingPathComponent(relativeRoot).standardizedFileURL.path
            return normalizedPath == root || normalizedPath.hasPrefix(root + "/")
        }
    }

    private func allowedRelativeRoots(for action: SupportedAction) -> [String] {
        let ruleRoots = BuiltInRules.all
            .filter { $0.action == .cleanup && $0.risk.isExecutable }
            .map(\.relativePath)
        let userRoots = ["Downloads", "Desktop"]

        switch action {
        case .cleanup:
            return ruleRoots + userRoots + orphanedApplicationStorageRoots
        case .uninstall:
            return ruleRoots + userRoots + applicationRoots
        case .none:
            return []
        }
    }

    private var orphanedApplicationStorageRoots: [String] {
        [
            "Library/Application Support",
            "Library/Caches",
            "Library/Logs",
            "Library/Containers",
            "Library/Saved Application State",
            "Library/Preferences"
        ]
    }

    private var applicationRoots: [String] {
        ["Applications", "Library/Application Support", "Library/Caches", "Library/Logs"]
    }

    private func isUnderSystemApplications(_ path: String) -> Bool {
        path == "/Applications" || path.hasPrefix("/Applications/")
    }
}
