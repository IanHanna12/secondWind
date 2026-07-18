import Foundation
import SecondWindCore

public struct RulePolicy: Codable, Sendable { public var disabledBuiltInRuleIDs: Set<String>; public var userRules: [UserCleanupRule]; public init(disabledBuiltInRuleIDs: Set<String> = [], userRules: [UserCleanupRule] = []) { self.disabledBuiltInRuleIDs = disabledBuiltInRuleIDs; self.userRules = userRules } }
public final class RulePolicyStore: @unchecked Sendable {
    public let url: URL
    public init(url: URL? = nil) { self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("SecondWind/rules.json") }
    public func policy() -> RulePolicy { guard let data = try? Data(contentsOf: url), let policy = try? JSONDecoder.secondWind.decode(RulePolicy.self, from: data) else { return .init() }; return policy }
    public func save(_ policy: RulePolicy) throws { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true); try JSONEncoder.secondWind.encode(policy).write(to: url, options: .atomic) }
    public func effectiveRules() -> [BuiltInRule] { let policy = policy(); return BuiltInRules.all.filter { !policy.disabledBuiltInRuleIDs.contains($0.id) } + policy.userRules.filter(\.isEnabled).map(\.builtInRule) }
}
