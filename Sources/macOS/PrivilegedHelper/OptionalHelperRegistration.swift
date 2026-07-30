import Foundation
import Security
import ServiceManagement

public enum SigningIdentity: Equatable, Sendable {
    case developerID(commonName: String)
    case other(commonName: String?)
    case unavailable

    public var description: String {
        switch self {
        case .developerID(let name): return name
        case .other(let name): return name ?? "Local or ad-hoc signature"
        case .unavailable: return "No signing identity detected"
        }
    }
}

public enum OptionalHelperState: Equatable, Sendable {
    case notBundled
    case notRegistered
    case requiresApproval
    case enabled
    case unavailable

    public var description: String {
        switch self {
        case .notBundled: return "Not included in this source build"
        case .notRegistered: return "Bundled but not registered"
        case .requiresApproval: return "Awaiting administrator approval in System Settings"
        case .enabled: return "Enabled and available"
        case .unavailable: return "Helper status unavailable"
        }
    }
}

public struct OptionalPrivilegeStatus: Sendable {
    public let signingIdentity: SigningIdentity
    public let helperState: OptionalHelperState
    /// A locally development-signed helper can be tested after user approval.
    public var canRunHelperTasks: Bool { helperState == .enabled }
    /// Developer ID is needed for distributing a trusted direct-download build,
    /// not for exercising an approved helper on the developer's own Mac.
    public var isReadyForDirectDistribution: Bool {
        if case .developerID = signingIdentity { return helperState == .enabled }
        return false
    }
}

public struct OptionalPrivilegeDetector: Sendable {
    public static let helperPlistName = "org.secondwind.PrivilegedMaintenanceHelper.plist"
    public init() {}

    public func detect(bundle: Bundle = .main) -> OptionalPrivilegeStatus {
        let identity = signingIdentity(for: bundle.bundleURL)
        let helperPlistURL = bundle.bundleURL.appendingPathComponent("Contents/Library/LaunchDaemons/\(Self.helperPlistName)")
        guard FileManager.default.fileExists(atPath: helperPlistURL.path) else { return .init(signingIdentity: identity, helperState: .notBundled) }
        let service = SMAppService.daemon(plistName: Self.helperPlistName)
        let state: OptionalHelperState
        switch service.status {
        case .enabled: state = .enabled
        case .notRegistered: state = .notRegistered
        case .requiresApproval: state = .requiresApproval
        // Before first registration, macOS may report `.notFound` even though
        // the app bundle contains the daemon plist. The explicit registration
        // action is the safe next step in that state.
        case .notFound: state = .notRegistered
        @unknown default: state = .unavailable
        }
        return .init(signingIdentity: identity, helperState: state)
    }

    private func signingIdentity(for url: URL) -> SigningIdentity {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else { return .unavailable }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(code, [], &information) == errSecSuccess,
              let dictionary = information as? [String: Any],
              let certificates = dictionary[kSecCodeInfoCertificates as String] as? [SecCertificate],
              let certificate = certificates.first else { return .unavailable }
        var commonName: CFString?
        SecCertificateCopyCommonName(certificate, &commonName)
        let name = commonName as String?
        guard let name, name.hasPrefix("Developer ID Application:") else { return .other(commonName: name) }
        return .developerID(commonName: name)
    }
}

public enum OptionalHelperRegistrationError: LocalizedError, Sendable {
    case notBundled

    public var errorDescription: String? {
        switch self {
        case .notBundled: return "This app build does not include the optional privileged helper. Build the App scheme from Xcode first."
        }
    }
}

/// Registration is intentionally explicit. Calling this is the only point at
/// which Second Wind asks macOS to make the optional root daemon available.
public struct OptionalHelperRegistration: Sendable {
    public init() {}

    public func register(bundle: Bundle = .main) throws {
        let helperPlistURL = bundle.bundleURL.appendingPathComponent("Contents/Library/LaunchDaemons/\(OptionalPrivilegeDetector.helperPlistName)")
        guard FileManager.default.fileExists(atPath: helperPlistURL.path) else { throw OptionalHelperRegistrationError.notBundled }
        try SMAppService.daemon(plistName: OptionalPrivilegeDetector.helperPlistName).register()
    }

    public func unregister() throws {
        try SMAppService.daemon(plistName: OptionalPrivilegeDetector.helperPlistName).unregister()
    }

    public func openApprovalSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
