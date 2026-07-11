import Foundation
import Darwin
import SecondWindCore
import SecondWindInfrastructure

public struct InstalledApplication: Identifiable, Hashable, Sendable {
    public let url: URL
    public let bundleIdentifier: String?
    public let displayName: String
    public var id: String { url.path }

    public init(url: URL, bundleIdentifier: String?, displayName: String) {
        self.url = url
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
    }
}
public struct AppRemnant: Identifiable, Hashable, Sendable {
    public let url: URL
    public let byteSize: Int64
    public let isExactKnownRemnant: Bool
    public let explanation: String
    public var id: String { url.path }

    public init(url: URL, byteSize: Int64, isExactKnownRemnant: Bool, explanation: String) {
        self.url = url
        self.byteSize = byteSize
        self.isExactKnownRemnant = isExactKnownRemnant
        self.explanation = explanation
    }
}
public struct ApplicationRemovalPreview: Sendable {
    public let application: InstalledApplication
    public let applicationBytes: Int64
    public let remnants: [AppRemnant]

    public var exactRemnants: [AppRemnant] { remnants.filter(\.isExactKnownRemnant) }
    public var protectedRemnants: [AppRemnant] { remnants.filter { !$0.isExactKnownRemnant } }
    public var exactRemnantBytes: Int64 { exactRemnants.reduce(0) { $0 + $1.byteSize } }
    public var removableBytes: Int64 { applicationBytes + exactRemnantBytes }
}
public struct ApplicationInventory: @unchecked Sendable {
    private let fileManager: FileManager
    private let home: URL
    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser, fileManager: FileManager = .default) {
        self.home = home
        self.fileManager = fileManager
    }
    public func applications() -> [InstalledApplication] {
        let roots = [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")]
        return roots.flatMap { (try? fileManager.contentsOfDirectory(at: $0, includingPropertiesForKeys: nil)) ?? [] }.filter { $0.pathExtension == "app" }.map { url in
            let bundle = Bundle(url: url); return InstalledApplication(url: url, bundleIdentifier: bundle?.bundleIdentifier, displayName: (bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String) ?? url.deletingPathExtension().lastPathComponent)
        }.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
    public func remnants(for app: InstalledApplication) -> [AppRemnant] {
        guard let identifier = app.bundleIdentifier else { return [] }
        let localFileSystem = LocalFileSystem(fileManager: fileManager)
        let exact = ["Library/Application Support/\(identifier)", "Library/Caches/\(identifier)", "Library/Logs/\(identifier)"]
        let exactItems = exact.map { home.appendingPathComponent($0) }.filter { fileManager.fileExists(atPath: $0.path) }.map { AppRemnant(url: $0, byteSize: localFileSystem.fileSize(at: $0), isExactKnownRemnant: true, explanation: "Exact support path for bundle identifier \(identifier).") }
        let ambiguous = [home.appendingPathComponent("Library/Application Support/\(app.displayName)")].filter { fileManager.fileExists(atPath: $0.path) }.map { AppRemnant(url: $0, byteSize: localFileSystem.fileSize(at: $0), isExactKnownRemnant: false, explanation: "Name-based match; select it individually only after review.") }
        return exactItems + ambiguous
    }
    public func removalPreview(for app: InstalledApplication) -> ApplicationRemovalPreview {
        ApplicationRemovalPreview(
            application: app,
            applicationBytes: LocalFileSystem(fileManager: fileManager).fileSize(at: app.url),
            remnants: remnants(for: app)
        )
    }
    public func uninstallFindings(for app: InstalledApplication) -> [Finding] {
        let preview = removalPreview(for: app)
        let appFinding = Finding(ruleID: "application-inventory", ruleVersion: BuiltInRules.version, title: "Application: \(app.displayName)", path: app.url.path, byteSize: preview.applicationBytes, category: .applications, origin: "Application inventory", explanation: "The selected application bundle.", risk: .reviewRequired, supportedAction: .uninstall, confidence: .exact)
        let remnantFindings = preview.remnants.map { remnant in
            Finding(ruleID: "application-remnant", ruleVersion: BuiltInRules.version, title: "Support files for \(app.displayName)", path: remnant.url.path, byteSize: remnant.byteSize, category: .applications, origin: "Application inventory", explanation: remnant.explanation, risk: remnant.isExactKnownRemnant ? .reviewRequired : .protected, supportedAction: remnant.isExactKnownRemnant ? .uninstall : .none, confidence: remnant.isExactKnownRemnant ? .exact : .needsUserReview)
        }
        return [appFinding] + remnantFindings
    }
}

public enum MaintenanceTask: String, Codable, CaseIterable, Identifiable, Sendable {
    case periodicScripts, rebuildSpotlightIndex, verifyVolume
    public var id: String { rawValue }
    public var title: String { switch self { case .periodicScripts: return "Run periodic maintenance scripts"; case .rebuildSpotlightIndex: return "Rebuild Spotlight index"; case .verifyVolume: return "Verify local volume" } }
    public var explanation: String { switch self { case .periodicScripts: return "Runs macOS's curated periodic maintenance task."; case .rebuildSpotlightIndex: return "Rebuilds the metadata index for the selected local volume."; case .verifyVolume: return "Checks an eligible local volume for filesystem errors." } }
}
public struct VolumeReference: Codable, Hashable, Sendable { public let url: URL; public let uuid: UUID?; public let isLocal: Bool; public init(url: URL) { self.url = url; let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeIsLocalKey]); self.uuid = values?.volumeUUIDString.flatMap(UUID.init(uuidString:)); self.isLocal = values?.volumeIsLocal ?? false }; public init(url: URL, uuid: UUID?, isLocal: Bool) { self.url = url; self.uuid = uuid; self.isLocal = isLocal } }
public enum MaintenanceValidationError: LocalizedError { case remoteVolume, missingUUID, unsupported
    public var errorDescription: String? { switch self { case .remoteVolume: return "Only a local volume may be selected."; case .missingUUID: return "The selected volume has no stable identifier."; case .unsupported: return "This task is not supported by the privileged helper." } }
}
public struct MaintenancePreflight: Sendable {
    public init() {}
    public func validate(task: MaintenanceTask, volume: VolumeReference?) throws {
        switch task {
        case .periodicScripts: return
        case .rebuildSpotlightIndex, .verifyVolume:
            guard let volume else { throw MaintenanceValidationError.missingUUID }
            guard volume.isLocal else { throw MaintenanceValidationError.remoteVolume }
            guard volume.uuid != nil else { throw MaintenanceValidationError.missingUUID }
        }
    }
}

/// Contract shared with the privileged helper. No command string or arbitrary path crosses this boundary.
public struct PrivilegedMaintenanceRequest: Codable, Sendable { public let task: MaintenanceTask; public let volumeUUID: UUID?; public init(task: MaintenanceTask, volumeUUID: UUID?) { self.task = task; self.volumeUUID = volumeUUID } }
public protocol PrivilegedMaintenanceClient: Sendable { func run(_ request: PrivilegedMaintenanceRequest) async throws }

public struct MaintenanceExecutionResult: Sendable {
    public let task: MaintenanceTask
    public let succeeded: Bool
    public let output: String
}

public enum MaintenanceRunnerError: LocalizedError { case launchFailed, rejected(String)
    public var errorDescription: String? { switch self { case .launchFailed: return "macOS could not start this maintenance task."; case .rejected(let text): return text } }
}

/// Debug/local runner. Each task maps to fixed executable paths and fixed arguments;
/// caller input can select only an enum task and a prevalidated mounted-volume URL.
public struct LocalMaintenanceRunner: Sendable {
    public init() {}
    public func run(task: MaintenanceTask, volume: VolumeReference?) throws -> MaintenanceExecutionResult {
        try MaintenancePreflight().validate(task: task, volume: volume)
        let commands: [(String, [String])]
        switch task {
        case .periodicScripts:
            commands = [("/usr/sbin/periodic", ["daily"]), ("/usr/sbin/periodic", ["weekly"]), ("/usr/sbin/periodic", ["monthly"])]
        case .rebuildSpotlightIndex:
            guard let volume else { throw MaintenanceRunnerError.rejected("Select a local volume first.") }
            commands = [("/usr/bin/mdutil", ["-E", volume.url.path])]
        case .verifyVolume:
            guard let volume else { throw MaintenanceRunnerError.rejected("Select a local volume first.") }
            commands = [("/usr/sbin/diskutil", ["verifyVolume", volume.url.path])]
        }
        var output = ""
        var succeeded = true
        for (executable, arguments) in commands {
            let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = pipe
            do { try process.run() } catch { throw MaintenanceRunnerError.launchFailed }
            let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
            output += String(data: data, encoding: .utf8) ?? ""
            succeeded = succeeded && process.terminationStatus == 0
        }
        return MaintenanceExecutionResult(task: task, succeeded: succeeded, output: output.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

public enum StewardPreference: String, CaseIterable, Identifiable, Sendable { case showFilenameExtensions, showHiddenFiles, dockAutohide, minimizeToApplication
    public var id: String { rawValue }
    public var explanation: String { switch self { case .showFilenameExtensions: return "Shows file extensions in Finder."; case .showHiddenFiles: return "Shows normally hidden files in Finder."; case .dockAutohide: return "Automatically hides the Dock."; case .minimizeToApplication: return "Keeps minimized windows in their app's Dock icon." } }
    fileprivate var domain: String { self == .showHiddenFiles ? "com.apple.finder" : self == .showFilenameExtensions ? "NSGlobalDomain" : "com.apple.dock" }
    fileprivate var key: String { switch self { case .showFilenameExtensions: return "AppleShowAllExtensions"; case .showHiddenFiles: return "AppleShowAllFiles"; case .dockAutohide: return "autohide"; case .minimizeToApplication: return "minimize-to-application" } }
}
public struct PreferenceService: Sendable {
    public init() {}
    public func isSupported(_ preference: StewardPreference) -> Bool { ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 13 }
    public func value(_ preference: StewardPreference) -> Bool? { UserDefaults.standard.persistentDomain(forName: preference.domain)?[preference.key] as? Bool }
    public func set(_ preference: StewardPreference, enabled: Bool) { var domain = UserDefaults.standard.persistentDomain(forName: preference.domain) ?? [:]; domain[preference.key] = enabled; UserDefaults.standard.setPersistentDomain(domain, forName: preference.domain) }
    public func reset(_ preference: StewardPreference) { var domain = UserDefaults.standard.persistentDomain(forName: preference.domain) ?? [:]; domain.removeValue(forKey: preference.key); UserDefaults.standard.setPersistentDomain(domain, forName: preference.domain) }
}

public struct ProcessUsage: Identifiable, Hashable, Sendable {
    public let pid: Int
    public let command: String
    public let cpuPercent: Double
    public let residentMemoryBytes: Int64
    public var id: Int { pid }
}
public struct DashboardSnapshot: Sendable { public let storageTotal: Int64; public let storageAvailable: Int64; public let physicalMemory: UInt64; public let activeProcessors: Int; public let loadAverage: Double; public let topProcesses: [ProcessUsage]; public let capturedAt: Date
    public var storageUsed: Int64 { max(0, storageTotal - storageAvailable) }
}
public struct MonitorService: Sendable {
    public init() {}
    public func snapshot(includeProcesses: Bool = false) -> DashboardSnapshot {
        let values = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey])
        var loads = [Double](repeating: 0, count: 3)
        _ = getloadavg(&loads, 3)
        return DashboardSnapshot(storageTotal: Int64(values?.volumeTotalCapacity ?? 0), storageAvailable: Int64(values?.volumeAvailableCapacityForImportantUsage ?? 0), physicalMemory: ProcessInfo.processInfo.physicalMemory, activeProcessors: ProcessInfo.processInfo.activeProcessorCount, loadAverage: loads[0], topProcesses: includeProcesses ? topProcesses() : [], capturedAt: Date())
    }
    private func topProcesses() -> [ProcessUsage] {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/bin/ps"); process.arguments = ["-axo", "pid=,pcpu=,rss=,comm="]
        let output = Pipe(); let errors = Pipe(); process.standardOutput = output; process.standardError = errors
        guard (try? process.run()) != nil else { return [] }
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return text.split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 3, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 4, let pid = Int(fields[0]), let cpu = Double(fields[1]), let rss = Int64(fields[2]) else { return nil }
            return ProcessUsage(pid: pid, command: String(fields[3]), cpuPercent: cpu, residentMemoryBytes: rss * 1024)
        }.sorted { $0.cpuPercent > $1.cpuPercent }.prefix(5).map { $0 }
    }
}
