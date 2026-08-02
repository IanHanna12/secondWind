import Foundation

/// User-editable policy for selecting built-in rules and defining local rules.
/// It cannot alter DeletionPolicy's internal safety boundaries.
public struct RulePolicy: Codable, Policy {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var disabledBuiltInRuleIDs: Set<String>
    public var userRules: [UserCleanupRule]

    public init(
        schemaVersion: Int = RulePolicy.currentSchemaVersion,
        disabledBuiltInRuleIDs: Set<String> = [],
        userRules: [UserCleanupRule] = []
    ) {
        self.schemaVersion = schemaVersion
        self.disabledBuiltInRuleIDs = disabledBuiltInRuleIDs
        self.userRules = userRules
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case disabledBuiltInRuleIDs
        case userRules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 0
        guard schemaVersion <= Self.currentSchemaVersion else {
            throw OperationFailure.unsupportedFutureFormat(document: "Rules")
        }
        disabledBuiltInRuleIDs = try container.decodeIfPresent(Set<String>.self, forKey: .disabledBuiltInRuleIDs) ?? []
        userRules = try container.decodeIfPresent([UserCleanupRule].self, forKey: .userRules) ?? []
    }
}

/// A user intention that changes the locally stored rule policy. Callers do
/// not construct and replace the complete durable document.
public enum RulePolicyChange: Sendable {
    case builtInRule(id: String, enabled: Bool)
    case addUserRule(title: String, route: SafeCleanupRoute, explanation: String)
    case userRule(id: UUID, enabled: Bool)
    case removeUserRules(ids: Set<UUID>)
}

/// Internal safety policy for cleanup execution. User rules can identify
/// candidates, but cannot broaden these deletion boundaries.
public struct DeletionPolicy: Policy {
    public init() {}

    public func permits(
        _ finding: Finding,
        destination: PlanDestination,
        home: URL
    ) -> Bool {
        if finding.ruleID == "orphaned-application-storage" {
            return finding.supportedAction == .cleanup &&
                destination != .systemTask &&
                OrphanedApplicationStoragePolicy.permitsCleanup(path: finding.path, home: home)
        }
        return permits(
            path: finding.path,
            action: finding.supportedAction,
            destination: destination,
            home: home
        )
    }

    public func permits(
        _ action: PlanAction,
        destination: PlanDestination,
        home: URL
    ) -> Bool {
        if action.ruleID == "orphaned-application-storage" {
            return action.action == .cleanup &&
                destination != .systemTask &&
                OrphanedApplicationStoragePolicy.permitsCleanup(path: action.sourcePath, home: home)
        }
        return permits(
            path: action.sourcePath,
            action: action.action,
            destination: destination,
            home: home
        )
    }

    private func permits(
        path: String,
        action: SupportedAction,
        destination: PlanDestination,
        home: URL
    ) -> Bool {
        guard destination != .systemTask else { return false }
        let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path

        if action == .uninstall, isUnderSystemApplications(normalizedPath) {
            return true
        }

        return allowedRelativeRoots(for: action).contains { relativeRoot in
            let root = home
                .appendingPathComponent(relativeRoot)
                .standardizedFileURL
                .path
            return normalizedPath == root || normalizedPath.hasPrefix(root + "/")
        }
    }

    private func allowedRelativeRoots(
        for action: SupportedAction
    ) -> [String] {
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
        [
            "Applications",
            "Library/Application Support",
            "Library/Caches",
            "Library/Logs"
        ]
    }

    private func isUnderSystemApplications(_ path: String) -> Bool {
        path == "/Applications" || path.hasPrefix("/Applications/")
    }
}
