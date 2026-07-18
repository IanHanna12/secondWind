import Foundation

public enum SafeCleanupRoute: String, Codable, CaseIterable, Identifiable, Sendable {
    case userLogs = "Library/Logs"
    case userCaches = "Library/Caches"
    case xcodeDerivedData = "Library/Developer/Xcode/DerivedData"
    case gradleCaches = ".gradle/caches"
    case npmCache = ".npm/_cacache"

    public var id: String { rawValue }
    public var title: String { rawValue }
}

public struct UserCleanupRule: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public var route: SafeCleanupRoute
    public var explanation: String
    public var isEnabled: Bool

    public init(id: UUID = UUID(), title: String, route: SafeCleanupRoute, explanation: String, isEnabled: Bool = true) {
        self.id = id; self.title = title; self.route = route; self.explanation = explanation; self.isEnabled = isEnabled
    }

    public var builtInRule: BuiltInRule {
        .init(id: "user-route-\(id.uuidString.lowercased())", title: title, relativePath: route.rawValue, category: .developer, risk: .safe, action: .cleanup, explanation: explanation)
    }
}
