import Foundation

/// Versioned, bundled safety policy. The application layer evaluates these
/// rules; the policy itself remains independent of filesystem APIs.
public enum FindingScope: String, Codable, Hashable, Sendable {
    case root
    case immediateChildren
}

public struct BuiltInRule: Codable, Hashable, Sendable {
    public let id: String
    public let version: Int
    public let title: String
    public let relativePath: String
    public let category: FindingCategory
    public let risk: Risk
    public let action: SupportedAction
    public let confidence: MatchConfidence
    public let explanation: String
    public let trashEligible: Bool
    public let findingScope: FindingScope

    public init(id: String, version: Int = 1, title: String, relativePath: String, category: FindingCategory, risk: Risk, action: SupportedAction, confidence: MatchConfidence = .exact, explanation: String, trashEligible: Bool = false, findingScope: FindingScope = .root) {
        self.id = id
        self.version = version
        self.title = title
        self.relativePath = relativePath
        self.category = category
        self.risk = risk
        self.action = action
        self.confidence = confidence
        self.explanation = explanation
        self.trashEligible = trashEligible
        self.findingScope = findingScope
    }
}

public enum BuiltInRules {
    public static let version = 1
    public static let all: [BuiltInRule] = [
        .init(id: "user-logs", version: 2, title: "User diagnostic logs", relativePath: "Library/Logs", category: .logs, risk: .safe, action: .cleanup, explanation: "User diagnostic logs are recreated when applications need them.", findingScope: .immediateChildren),
        .init(id: "xcode-derived-data", version: 2, title: "Xcode Derived Data", relativePath: "Library/Developer/Xcode/DerivedData", category: .developer, risk: .safe, action: .cleanup, explanation: "Xcode build artifacts are recreated on demand.", findingScope: .immediateChildren),
        .init(id: "xcode-device-support", version: 2, title: "Xcode device support files", relativePath: "Library/Developer/Xcode/iOS DeviceSupport", category: .developer, risk: .safe, action: .cleanup, explanation: "Xcode can recreate device support files when a connected device needs them.", findingScope: .immediateChildren),
        .init(id: "core-simulator-caches", version: 2, title: "Core Simulator caches", relativePath: "Library/Developer/CoreSimulator/Caches", category: .developer, risk: .safe, action: .cleanup, explanation: "Simulator cache data is recreated as needed; simulator devices and their app data are not included.", findingScope: .immediateChildren),
        .init(id: "gradle-cache", version: 2, title: "Gradle cache", relativePath: ".gradle/caches", category: .developer, risk: .safe, action: .cleanup, explanation: "Downloaded Gradle dependencies and build caches can be recreated.", findingScope: .immediateChildren),
        .init(id: "gradle-wrapper-cache", version: 2, title: "Gradle wrapper distributions", relativePath: ".gradle/wrapper/dists", category: .developer, risk: .safe, action: .cleanup, explanation: "Cached Gradle distributions can be downloaded again by the wrapper.", findingScope: .immediateChildren),
        .init(id: "npm-cache", version: 2, title: "npm cache", relativePath: ".npm/_cacache", category: .packageManagers, risk: .safe, action: .cleanup, explanation: "npm can recreate downloaded package cache data.", findingScope: .immediateChildren),
        .init(id: "yarn-cache", version: 2, title: "Yarn cache", relativePath: "Library/Caches/Yarn", category: .packageManagers, risk: .safe, action: .cleanup, explanation: "Yarn can download cached packages again when a project needs them.", findingScope: .immediateChildren),
        .init(id: "pip-cache", version: 2, title: "pip cache", relativePath: "Library/Caches/pip", category: .packageManagers, risk: .safe, action: .cleanup, explanation: "pip can recreate downloaded Python packages when they are installed again.", findingScope: .immediateChildren),
        .init(id: "cargo-registry-cache", version: 2, title: "Cargo registry cache", relativePath: ".cargo/registry/cache", category: .packageManagers, risk: .safe, action: .cleanup, explanation: "Cargo can download registry package archives again when a Rust project needs them.", findingScope: .immediateChildren),
        .init(id: "cocoapods-cache", version: 2, title: "CocoaPods cache", relativePath: "Library/Caches/CocoaPods", category: .packageManagers, risk: .safe, action: .cleanup, explanation: "CocoaPods can fetch cached pod archives again when dependencies are installed.", findingScope: .immediateChildren),
        .init(id: "homebrew-cache", version: 2, title: "Homebrew cache", relativePath: "Library/Caches/Homebrew", category: .packageManagers, risk: .safe, action: .cleanup, explanation: "Homebrew downloads can be fetched again.", findingScope: .immediateChildren),
        .init(id: "docker-data", title: "Docker Desktop data", relativePath: "Library/Containers/com.docker.docker", category: .containers, risk: .protected, action: .none, confidence: .needsUserReview, explanation: "Docker volumes may contain irreplaceable databases. This app never removes them."),
        .init(id: "xcode-archives", version: 2, title: "Xcode Archives", relativePath: "Library/Developer/Xcode/Archives", category: .developer, risk: .reviewRequired, action: .cleanup, confidence: .needsUserReview, explanation: "Archives can be distribution artifacts; review them individually.", findingScope: .immediateChildren),
        .init(id: "simulator-devices", version: 2, title: "Simulator devices", relativePath: "Library/Developer/CoreSimulator/Devices", category: .developer, risk: .reviewRequired, action: .cleanup, confidence: .needsUserReview, explanation: "Simulator devices can contain app state and test data.", findingScope: .immediateChildren),
        .init(id: "browser-data", title: "Browser data", relativePath: "Library/Application Support/Google/Chrome", category: .browsers, risk: .protected, action: .none, confidence: .needsUserReview, explanation: "Browser profiles may contain active sessions and user data."),
        .init(id: "trash", title: "Finder Trash", relativePath: ".Trash", category: .system, risk: .reviewRequired, action: .none, explanation: "Use Finder to review and empty the Trash intentionally.")
    ]
}

/// A local rule can select only a known safe route. It never changes the
/// deletion policy that governs plan execution.
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

    public init(
        id: UUID = UUID(),
        title: String,
        route: SafeCleanupRoute,
        explanation: String,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.route = route
        self.explanation = explanation
        self.isEnabled = isEnabled
    }

    public var builtInRule: BuiltInRule {
        BuiltInRule(
            id: "user-route-\(id.uuidString.lowercased())",
            title: title,
            relativePath: route.rawValue,
            category: .developer,
            risk: .safe,
            action: .cleanup,
            explanation: explanation
        )
    }
}
