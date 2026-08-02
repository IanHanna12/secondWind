import Foundation
import SecondWindCore

public enum RulePolicyError: LocalizedError, Equatable, Sendable {
    case invalidTitle
    case invalidExplanation
    case duplicateRule(UUID)
    case unknownBuiltInRule(String)
    case unknownUserRule(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidTitle: return "A local rule needs a title."
        case .invalidExplanation: return "A local rule needs an explanation of what it observes."
        case let .duplicateRule(id): return "The local rule \(id.uuidString) appears more than once."
        case let .unknownBuiltInRule(id): return "The stored policy refers to unknown built-in rule \(id)."
        case let .unknownUserRule(id): return "The local rule \(id.uuidString) no longer exists."
        }
    }
}

public final class RulePolicyStore: Store, @unchecked Sendable {
    public let url: URL
    public init(url: URL? = nil) { self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SecondWind/rules.json") }

    /// Corrupt or unsupported files are deliberately left untouched. Built-in
    /// rules remain the safe fallback until a person resolves the problem.
    public func policy() -> RulePolicy {
        (try? load()) ?? .init()
    }

    public func load() throws -> RulePolicy {
        guard FileManager.default.fileExists(atPath: url.path) else { return .init() }
        let data = try Data(contentsOf: url)
        do {
            let policy = try JSONDecoder.secondWind.decode(RulePolicy.self, from: data)
            try validate(policy)
            return policy
        } catch let failure as OperationFailure {
            throw failure
        } catch let failure as RulePolicyError {
            throw failure
        } catch {
            throw PersistenceDocumentError.corrupt(document: "rule policy")
        }
    }

    public func validate(_ policy: RulePolicy) throws {
        let knownBuiltInRuleIDs = Set(BuiltInRules.all.map(\.id))
        if let unknownRuleID = policy.disabledBuiltInRuleIDs.first(where: { !knownBuiltInRuleIDs.contains($0) }) {
            throw RulePolicyError.unknownBuiltInRule(unknownRuleID)
        }
        var identifiers = Set<UUID>()
        for rule in policy.userRules {
            guard !rule.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RulePolicyError.invalidTitle }
            guard !rule.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RulePolicyError.invalidExplanation }
            guard identifiers.insert(rule.id).inserted else { throw RulePolicyError.duplicateRule(rule.id) }
        }
    }

    @discardableResult
    public func apply(_ change: RulePolicyChange) throws -> RulePolicy {
        try updatePolicy { policy in
            switch change {
            case let .builtInRule(id, enabled):
                if enabled {
                    policy.disabledBuiltInRuleIDs.remove(id)
                } else {
                    policy.disabledBuiltInRuleIDs.insert(id)
                }
            case let .addUserRule(title, route, explanation):
                policy.userRules.append(
                    UserCleanupRule(title: title, route: route, explanation: explanation)
                )
            case let .userRule(id, enabled):
                guard let index = policy.userRules.firstIndex(where: { $0.id == id }) else {
                    throw RulePolicyError.unknownUserRule(id)
                }
                policy.userRules[index].isEnabled = enabled
            case let .removeUserRules(ids):
                policy.userRules.removeAll { ids.contains($0.id) }
            }
        }
    }

    private func updatePolicy(_ update: (inout RulePolicy) throws -> Void) throws -> RulePolicy {
        var policy = try load()
        try update(&policy)
        try write(policy)
        return policy
    }

    private func write(_ policy: RulePolicy) throws {
        try validate(policy)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var value = policy
        value.schemaVersion = RulePolicy.currentSchemaVersion
        try JSONEncoder.secondWind.encode(value).write(to: url, options: .atomic)
    }

    public func effectiveRules() -> [BuiltInRule] {
        let policy = policy()
        return BuiltInRules.all.filter { !policy.disabledBuiltInRuleIDs.contains($0.id) } + policy.userRules.filter(\.isEnabled).map(\.builtInRule)
    }
}
