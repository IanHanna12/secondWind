import Darwin
import Foundation
import OSLog
import Security
import SecondWindCore
import SecondWindSystem
import SecondWindPlatform

/// Root-side implementation of deliberately narrow, typed helper operations.
/// Commands and arbitrary filesystem paths never cross this XPC boundary.
final class PrivilegedMaintenanceService: NSObject, PrivilegedMaintenanceXPC {
    private let requestValidator = HelperRequestValidator()
    private let applicationTrashMover = PrivilegedApplicationTrashMover()
    private let callerProcessIdentifier: Int32

    init(callerProcessIdentifier: Int32) {
        self.callerProcessIdentifier = callerProcessIdentifier
    }

    func perform(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        do {
            let request = try JSONDecoder.secondWind.decode(PrivilegedMaintenanceRequest.self, from: requestData)
            let volumes = FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: [.volumeUUIDStringKey, .volumeIsLocalKey],
                options: []
            )?.map(VolumeReference.init) ?? []
            try requestValidator.validate(request, mountedVolumes: volumes)

            let selectedVolume = request.volumeUUID.flatMap { requestedID in
                volumes.first { $0.uuid == requestedID }
            }
            let result = try LocalMaintenanceRunner().run(task: request.task, volume: selectedVolume)
            let response = PrivilegedMaintenanceReply(task: result.task, succeeded: result.succeeded, output: result.output)
            reply(try JSONEncoder.secondWind.encode(response), nil)
        } catch {
            reply(nil, error as NSError)
        }
    }

    func moveApplicationToTrash(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void) {
        do {
            let request = try JSONDecoder.secondWind.decode(PrivilegedApplicationTrashRequest.self, from: requestData)
            let trashURL = try applicationTrashMover.moveApplicationToTrash(
                request,
                callerProcessIdentifier: callerProcessIdentifier
            )
            let response = PrivilegedApplicationTrashReply(trashPath: trashURL.path)
            reply(try JSONEncoder.secondWind.encode(response), nil)
        } catch {
            reply(nil, error as NSError)
        }
    }
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    private let callerValidator = SignedCallerValidator()
    private let logger = Logger(subsystem: "org.secondwind.app", category: "privileged-helper")

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        do {
            try callerValidator.validate(connection: connection)
            connection.exportedInterface = NSXPCInterface(with: PrivilegedMaintenanceXPC.self)
            connection.exportedObject = PrivilegedMaintenanceService(callerProcessIdentifier: connection.processIdentifier)
            connection.resume()
            return true
        } catch {
            logger.error("Rejected XPC caller \(connection.processIdentifier, privacy: .public): \(error.localizedDescription, privacy: .public)")
            // Reject before the caller receives an exported object. The app will
            // see the unavailable-helper error and write a local audit receipt.
            return false
        }
    }
}

private enum PrivilegedApplicationTrashMoverError: LocalizedError {
    case invalidApplication
    case invalidCaller
    case unavailableUserTrash

    var errorDescription: String? {
        switch self {
        case .invalidApplication: return "The helper accepts only a verified app bundle directly inside /Applications."
        case .invalidCaller: return "The helper could not identify the signed-in caller for this app removal."
        case .unavailableUserTrash: return "The signed-in user's Finder Trash is unavailable."
        }
    }
}

/// Moves only an app selected by Second Wind from `/Applications` into the
/// connecting user's Finder Trash. The caller's identity comes from its Darwin
/// process record, never from the XPC request.
private struct PrivilegedApplicationTrashMover {
    private let applicationsDirectory = URL(fileURLWithPath: "/Applications").standardizedFileURL
    private let processOwnerResolver = DarwinProcessOwnerResolver()
    private let fileManager = FileManager.default

    func moveApplicationToTrash(
        _ request: PrivilegedApplicationTrashRequest,
        callerProcessIdentifier: Int32
    ) throws -> URL {
        let applicationURL = URL(fileURLWithPath: request.applicationPath).standardizedFileURL
        guard applicationURL.deletingLastPathComponent() == applicationsDirectory,
              applicationURL.pathExtension == "app",
              (try? applicationURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]).isDirectory) == true,
              (try? applicationURL.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true,
              Bundle(url: applicationURL)?.bundleIdentifier == request.bundleIdentifier else {
            throw PrivilegedApplicationTrashMoverError.invalidApplication
        }

        guard let callerOwner = processOwnerResolver.resolveOwner(for: callerProcessIdentifier),
              callerOwner.userID != 0,
              let userHomeDirectory = homeDirectory(for: callerOwner.userID) else {
            throw PrivilegedApplicationTrashMoverError.invalidCaller
        }
        let userTrashDirectory = userHomeDirectory.appendingPathComponent(".Trash", isDirectory: true)
        try ensureUserTrashExists(at: userTrashDirectory, owner: callerOwner)

        let trashDestination = availableTrashDestination(
            for: applicationURL.lastPathComponent,
            in: userTrashDirectory
        )
        try fileManager.moveItem(at: applicationURL, to: trashDestination)
        return trashDestination
    }

    private func homeDirectory(for userID: uid_t) -> URL? {
        guard let passwordEntry = getpwuid(userID) else { return nil }
        return URL(fileURLWithPath: String(cString: passwordEntry.pointee.pw_dir)).standardizedFileURL
    }

    private func ensureUserTrashExists(
        at userTrashDirectory: URL,
        owner: DarwinProcessOwnerResolver.ProcessOwner
    ) throws {
        if !fileManager.fileExists(atPath: userTrashDirectory.path) {
            try fileManager.createDirectory(at: userTrashDirectory, withIntermediateDirectories: true)
            guard lchown(userTrashDirectory.path, owner.userID, owner.groupID) == 0 else {
                throw PrivilegedApplicationTrashMoverError.unavailableUserTrash
            }
        }
        var information = stat()
        guard lstat(userTrashDirectory.path, &information) == 0,
              information.st_uid == owner.userID else {
            throw PrivilegedApplicationTrashMoverError.unavailableUserTrash
        }
    }

    private func availableTrashDestination(for fileName: String, in userTrashDirectory: URL) -> URL {
        let initialDestination = userTrashDirectory.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: initialDestination.path) else { return initialDestination }

        let baseName = initialDestination.deletingPathExtension().lastPathComponent
        let fileExtension = initialDestination.pathExtension
        let suffix = fileExtension.isEmpty ? "" : ".\(fileExtension)"
        return userTrashDirectory.appendingPathComponent("\(baseName) (Moved by Second Wind — \(UUID().uuidString))\(suffix)")
    }

}

private enum SignedCallerValidationError: LocalizedError {
    case unsignedHelper
    case unsignedCaller
    case invalidCaller

    var errorDescription: String? {
        switch self {
        case .unsignedHelper: return "The helper has no Apple development or Developer ID team signature."
        case .unsignedCaller: return "The XPC caller has no verifiable code signature."
        case .invalidCaller: return "The XPC caller does not satisfy the Second Wind designated requirement."
        }
    }
}

/// Checks the connecting process identifier supplied by NSXPCConnection, then
/// verifies that process is the signed Second Wind app from the same Apple
/// development team. Service Management also enforces the helper's
/// `SMAuthorizedClients` requirement before this delegate receives a client.
/// This is independent of request JSON and cannot be forged by a
/// client-controlled field.
private struct SignedCallerValidator {
    private let appIdentifier = "org.secondwind.app"
    private let processExecutableURLResolver = DarwinProcessExecutableURLResolver()

    func validate(connection: NSXPCConnection) throws {
        guard let executableURL = processExecutableURLResolver.resolveExecutableURL(for: connection.processIdentifier) else {
            throw SignedCallerValidationError.unsignedCaller
        }

        var clientCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &clientCode) == errSecSuccess,
              let clientCode else { throw SignedCallerValidationError.unsignedCaller }

        guard let teamIdentifier = helperTeamIdentifier() else {
            throw SignedCallerValidationError.unsignedHelper
        }
        let requirementText = "anchor apple generic and identifier \"\(appIdentifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(clientCode, [], requirement) == errSecSuccess else {
            throw SignedCallerValidationError.invalidCaller
        }
    }

    private func helperTeamIdentifier() -> String? {
        guard let executableURL = processExecutableURLResolver.resolveExecutableURL(for: getpid()) else { return nil }
        var helperCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &helperCode) == errSecSuccess, let helperCode else { return nil }
        var information: CFDictionary?
        let signingInformation = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(helperCode, signingInformation, &information) == errSecSuccess,
              let values = information as? [String: Any] else { return nil }
        return values[kSecCodeInfoTeamIdentifier as String] as? String
    }
}

@main
struct PrivilegedMaintenanceHelperMain {
    static func main() {
        let listener = NSXPCListener(machServiceName: XPCPrivilegedMaintenanceClient.serviceName)
        let delegate = HelperDelegate()
        listener.delegate = delegate
        listener.resume()
        RunLoop.current.run()
    }
}
