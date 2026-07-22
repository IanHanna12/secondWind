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
