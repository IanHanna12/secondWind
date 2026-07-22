import Foundation

public enum SystemPreference: String, CaseIterable, Identifiable, Sendable {
    case showFilenameExtensions
    case showHiddenFiles
    case dockAutohide
    case minimizeToApplication

    public var id: String { rawValue }

    public var explanation: String {
        switch self {
        case .showFilenameExtensions:
            return "Shows file extensions in Finder."
        case .showHiddenFiles:
            return "Shows normally hidden files in Finder."
        case .dockAutohide:
            return "Automatically hides the Dock."
        case .minimizeToApplication:
            return "Keeps minimized windows in their app's Dock icon."
        }
    }

    fileprivate var defaultsDomain: String {
        switch self {
        case .showFilenameExtensions:
            return "NSGlobalDomain"
        case .showHiddenFiles:
            return "com.apple.finder"
        case .dockAutohide, .minimizeToApplication:
            return "com.apple.dock"
        }
    }

    fileprivate var defaultsKey: String {
        switch self {
        case .showFilenameExtensions:
            return "AppleShowAllExtensions"
        case .showHiddenFiles:
            return "AppleShowAllFiles"
        case .dockAutohide:
            return "autohide"
        case .minimizeToApplication:
            return "minimize-to-application"
        }
    }
}

public struct PreferenceService: Sendable {
    public init() {}

    public func isSupported(_ preference: SystemPreference) -> Bool {
        _ = preference
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 13
    }

    public func value(_ preference: SystemPreference) -> Bool? {
        UserDefaults.standard
            .persistentDomain(forName: preference.defaultsDomain)?[preference.defaultsKey] as? Bool
    }

    public func set(_ preference: SystemPreference, enabled: Bool) {
        var domain = persistentDomain(for: preference)
        domain[preference.defaultsKey] = enabled
        UserDefaults.standard.setPersistentDomain(domain, forName: preference.defaultsDomain)
    }

    public func reset(_ preference: SystemPreference) {
        var domain = persistentDomain(for: preference)
        domain.removeValue(forKey: preference.defaultsKey)
        UserDefaults.standard.setPersistentDomain(domain, forName: preference.defaultsDomain)
    }

    private func persistentDomain(for preference: SystemPreference) -> [String: Any] {
        UserDefaults.standard.persistentDomain(forName: preference.defaultsDomain) ?? [:]
    }
}
