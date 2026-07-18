import Foundation

/// Logic intended for the XPC helper target. It validates a typed request before invoking its fixed implementation.
public struct HelperRequestValidator: Sendable {
    public init() {}
    public func validate(_ request: PrivilegedMaintenanceRequest, mountedVolumes: [VolumeReference]) throws {
        try MaintenancePreflight().validate(task: request.task, volume: request.volumeUUID.flatMap { id in mountedVolumes.first { $0.uuid == id } })
    }
}
