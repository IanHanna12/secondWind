import Foundation

/// Versioned, bundled safety policy. The application layer evaluates these
/// rules; the policy itself remains independent of filesystem APIs.
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

    public init(id: String, version: Int = 1, title: String, relativePath: String, category: FindingCategory, risk: Risk, action: SupportedAction, confidence: MatchConfidence = .exact, explanation: String, trashEligible: Bool = false) {
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
    }
}

public enum BuiltInRules {
    public static let version = 1
    public static let all: [BuiltInRule] = [
        .init(id: "user-logs", title: "User diagnostic logs", relativePath: "Library/Logs", category: .logs, risk: .safe, action: .cleanup, explanation: "User diagnostic logs are recreated when applications need them."),
        .init(id: "xcode-derived-data", title: "Xcode Derived Data", relativePath: "Library/Developer/Xcode/DerivedData", category: .developer, risk: .safe, action: .cleanup, explanation: "Xcode build artifacts are recreated on demand."),
        .init(id: "xcode-device-support", title: "Xcode device support files", relativePath: "Library/Developer/Xcode/iOS DeviceSupport", category: .developer, risk: .safe, action: .cleanup, explanation: "Xcode can recreate device support files when a connected device needs them."),
        .init(id: "core-simulator-caches", title: "Core Simulator caches", relativePath: "Library/Developer/CoreSimulator/Caches", category: .developer, risk: .safe, action: .cleanup, explanation: "Simulator cache data is recreated as needed; simulator devices and their app data are not included."),
        .init(id: "gradle-cache", title: "Gradle cache", relativePath: ".gradle/caches", category: .developer, risk: .safe, action: .cleanup, explanation: "Downloaded Gradle dependencies and build caches can be recreated."),
        .init(id: "gradle-wrapper-cache", title: "Gradle wrapper distributions", relativePath: ".gradle/wrapper/dists", category: .developer, risk: .safe, action: .cleanup, explanation: "Cached Gradle distributions can be downloaded again by the wrapper."),
        .init(id: "npm-cache", title: "npm cache", relativePath: ".npm/_cacache", category: .packageManagers, risk: .safe, action: .cleanup, explanation: "npm can recreate downloaded package cache data."),
        .init(id: "yarn-cache", title: "Yarn cache", relativePath: "Library/Caches/Yarn", category: .packageManagers, risk: .safe, action: .cleanup, explanation: "Yarn can download cached packages again when a project needs them."),
        .init(id: "pip-cache", title: "pip cache", relativePath: "Library/Caches/pip", category: .packageManagers, risk: .safe, action: .cleanup, explanation: "pip can recreate downloaded Python packages when they are installed again."),
        .init(id: "cargo-registry-cache", title: "Cargo registry cache", relativePath: ".cargo/registry/cache", category: .packageManagers, risk: .safe, action: .cleanup, explanation: "Cargo can download registry package archives again when a Rust project needs them."),
        .init(id: "cocoapods-cache", title: "CocoaPods cache", relativePath: "Library/Caches/CocoaPods", category: .packageManagers, risk: .safe, action: .cleanup, explanation: "CocoaPods can fetch cached pod archives again when dependencies are installed."),
        .init(id: "homebrew-cache", title: "Homebrew cache", relativePath: "Library/Caches/Homebrew", category: .packageManagers, risk: .safe, action: .cleanup, explanation: "Homebrew downloads can be fetched again."),
        .init(id: "docker-data", title: "Docker Desktop data", relativePath: "Library/Containers/com.docker.docker", category: .containers, risk: .protected, action: .none, confidence: .needsUserReview, explanation: "Docker volumes may contain irreplaceable databases. This app never removes them."),
        .init(id: "xcode-archives", title: "Xcode Archives", relativePath: "Library/Developer/Xcode/Archives", category: .developer, risk: .reviewRequired, action: .cleanup, confidence: .needsUserReview, explanation: "Archives can be distribution artifacts; review them individually."),
        .init(id: "simulator-devices", title: "Simulator devices", relativePath: "Library/Developer/CoreSimulator/Devices", category: .developer, risk: .reviewRequired, action: .cleanup, confidence: .needsUserReview, explanation: "Simulator devices can contain app state and test data."),
        .init(id: "browser-data", title: "Browser data", relativePath: "Library/Application Support/Google/Chrome", category: .browsers, risk: .protected, action: .none, confidence: .needsUserReview, explanation: "Browser profiles may contain active sessions and user data."),
        .init(id: "trash", title: "Finder Trash", relativePath: ".Trash", category: .system, risk: .reviewRequired, action: .none, explanation: "Use Finder to review and empty the Trash intentionally.")
    ]
}
