import Foundation
import SecondWindCore

public enum RulePolicyError: LocalizedError, Equatable, Sendable {
    case invalidTitle
    case invalidExplanation
    case duplicateRule(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidTitle: return "A local rule needs a title."
        case .invalidExplanation: return "A local rule needs an explanation of what it observes."
        case let .duplicateRule(id): return "The local rule \(id.uuidString) appears more than once."
        }
    }
}

public final class RulePolicyStore: Store, @unchecked Sendable {
    public let url: URL
    public init(url: URL? = nil) { self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SecondWind/rules.json") }

    /// Corrupt or unsupported files are deliberately left untouched. Built-in
    /// rules remain the safe fallback until a person resolves the problem.
    public func policy() -> RulePolicy {
        guard let data = try? Data(contentsOf: url), let policy = try? JSONDecoder.secondWind.decode(RulePolicy.self, from: data) else { return .init() }
        return policy
    }

    public func validate(_ policy: RulePolicy) throws {
        var identifiers = Set<UUID>()
        for rule in policy.userRules {
            guard !rule.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RulePolicyError.invalidTitle }
            guard !rule.explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw RulePolicyError.invalidExplanation }
            guard identifiers.insert(rule.id).inserted else { throw RulePolicyError.duplicateRule(rule.id) }
        }
    }

    public func save(_ policy: RulePolicy) throws {
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
