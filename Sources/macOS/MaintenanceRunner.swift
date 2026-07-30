import Foundation
import SecondWindCore

public enum MaintenanceTask: String, Codable, CaseIterable, Identifiable, Sendable {
    case periodicScripts
    case rebuildSpotlightIndex
    case verifyVolume

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .periodicScripts:
            return "Run periodic maintenance scripts"
        case .rebuildSpotlightIndex:
            return "Rebuild Spotlight index"
        case .verifyVolume:
            return "Verify local volume"
        }
    }

    public var explanation: String {
        switch self {
        case .periodicScripts:
            return "Runs macOS's legacy periodic scripts when they are provided by the operating system."
        case .rebuildSpotlightIndex:
            return "Enables Spotlight indexing if needed and rebuilds the metadata index for the selected volume."
        case .verifyVolume:
            return "Checks an eligible local volume for filesystem errors."
        }
    }

    public var isAvailable: Bool {
        self != .periodicScripts || FileManager.default.isExecutableFile(atPath: "/usr/sbin/periodic")
    }
}

public struct VolumeReference: Codable, Hashable, Sendable {
    public let url: URL
    public let uuid: UUID?
    public let isLocal: Bool

    public init(url: URL) {
        self.url = url
        let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .volumeIsLocalKey])
        uuid = values?.volumeUUIDString.flatMap(UUID.init(uuidString:))
        isLocal = values?.volumeIsLocal ?? false
    }

    public init(url: URL, uuid: UUID?, isLocal: Bool) {
        self.url = url
        self.uuid = uuid
        self.isLocal = isLocal
    }
}

public enum MaintenanceValidationError: LocalizedError {
    case remoteVolume
    case missingUUID
    case unsupported

    public var errorDescription: String? {
        switch self {
        case .remoteVolume:
            return "Only a local volume may be selected."
        case .missingUUID:
            return "The selected volume has no stable identifier."
        case .unsupported:
            return "This task is not supported by the privileged helper."
        }
    }
}

public struct MaintenancePreflight: Validator {
    public init() {}

    public func validate(task: MaintenanceTask, volume: VolumeReference?) throws {
        switch task {
        case .periodicScripts:
            guard task.isAvailable else {
                throw MaintenanceRunnerError.rejected("This macOS version does not provide manual periodic scripts.")
            }
        case .rebuildSpotlightIndex, .verifyVolume:
            try validateLocalVolume(volume)
        }
    }

    private func validateLocalVolume(_ volume: VolumeReference?) throws {
        guard let volume else { throw MaintenanceValidationError.missingUUID }
        guard volume.isLocal else { throw MaintenanceValidationError.remoteVolume }
        guard volume.uuid != nil else { throw MaintenanceValidationError.missingUUID }
    }
}

public struct PrivilegedMaintenanceRequest: Codable, Sendable {
    public let task: MaintenanceTask
    public let volumeUUID: UUID?

    public init(task: MaintenanceTask, volumeUUID: UUID?) {
        self.task = task
        self.volumeUUID = volumeUUID
    }
}

public protocol PrivilegedMaintenanceClient: Sendable {
    func run(_ request: PrivilegedMaintenanceRequest) async throws
}

public struct MaintenanceExecutionResult: Sendable {
    public let task: MaintenanceTask
    public let succeeded: Bool
    public let output: String
}

public enum MaintenanceRunnerError: LocalizedError {
    case launchFailed
    case rejected(String)

    public var errorDescription: String? {
        switch self {
        case .launchFailed:
            return "macOS could not start this maintenance task."
        case let .rejected(message):
            return message
        }
    }
}

public struct LocalMaintenanceRunner: Sendable {
    private typealias Command = (executable: String, arguments: [String])

    public init() {}

    public func run(task: MaintenanceTask, volume: VolumeReference?) throws -> MaintenanceExecutionResult {
        try MaintenancePreflight().validate(task: task, volume: volume)

        var combinedOutput = ""
        var allCommandsSucceeded = true
        for command in try commands(for: task, volume: volume) {
            let result = try run(command)
            combinedOutput += result.output
            allCommandsSucceeded = allCommandsSucceeded && result.succeeded
        }

        return MaintenanceExecutionResult(
            task: task,
            succeeded: allCommandsSucceeded,
            output: combinedOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private func commands(for task: MaintenanceTask, volume: VolumeReference?) throws -> [Command] {
        switch task {
        case .periodicScripts:
            return [
                ("/usr/sbin/periodic", ["daily"]),
                ("/usr/sbin/periodic", ["weekly"]),
                ("/usr/sbin/periodic", ["monthly"])
            ]
        case .rebuildSpotlightIndex:
            guard let volume else { throw MaintenanceRunnerError.rejected("Select a local volume first.") }
            return spotlightCommands(for: volume.url.path)
        case .verifyVolume:
            guard let volume else { throw MaintenanceRunnerError.rejected("Select a local volume first.") }
            return [("/usr/sbin/diskutil", ["verifyVolume", volume.url.path])]
        }
    }

    private func spotlightCommands(for path: String) -> [Command] {
        var commands: [Command] = [
            ("/usr/bin/mdutil", ["-i", "on", path]),
            ("/usr/bin/mdutil", ["-E", path])
        ]
        guard path == "/" else { return commands }
        commands += [
            ("/usr/bin/mdutil", ["-i", "on", "/System/Volumes/Data"]),
            ("/usr/bin/mdutil", ["-E", "/System/Volumes/Data"])
        ]
        return commands
    }

    private func run(_ command: Command) throws -> (succeeded: Bool, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: command.executable)
        process.arguments = command.arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            throw MaintenanceRunnerError.launchFailed
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus == 0, String(data: data, encoding: .utf8) ?? "")
    }
}
