import Foundation
import Security
import SecondWindCore
import SecondWindPlatform

/// Root-side implementation of the deliberately narrow maintenance contract.
/// No command string, executable path, or unvalidated filesystem path crosses
/// this XPC boundary.
final class PrivilegedMaintenanceService: NSObject, PrivilegedMaintenanceXPC {
    private let requestValidator = HelperRequestValidator()

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
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    private let callerValidator = SignedCallerValidator()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        do {
            try callerValidator.validate(connection: connection)
            connection.exportedInterface = NSXPCInterface(with: PrivilegedMaintenanceXPC.self)
            connection.exportedObject = PrivilegedMaintenanceService()
            connection.resume()
            return true
        } catch {
            // Reject before the caller receives an exported object. The app will
            // see the unavailable-helper error and write a local audit receipt.
            return false
        }
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

    func validate(connection: NSXPCConnection) throws {
        let attributes = [kSecGuestAttributePid: NSNumber(value: connection.processIdentifier)] as CFDictionary
        var clientCode: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &clientCode) == errSecSuccess,
              let clientCode else {
            throw SignedCallerValidationError.unsignedCaller
        }

        guard let teamIdentifier = helperTeamIdentifier() else {
            throw SignedCallerValidationError.unsignedHelper
        }
        let requirementText = "anchor apple generic and identifier \"\(appIdentifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecCodeCheckValidity(clientCode, [], requirement) == errSecSuccess else {
            throw SignedCallerValidationError.invalidCaller
        }
    }

    private func helperTeamIdentifier() -> String? {
        let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        var helperCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(executableURL as CFURL, [], &helperCode) == errSecSuccess, let helperCode else { return nil }
        var information: CFDictionary?
        guard SecCodeCopySigningInformation(helperCode, [], &information) == errSecSuccess,
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
