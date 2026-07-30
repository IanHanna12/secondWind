import Darwin
import Foundation
import SecondWindCore

/// Resolves a process identifier to the executable path reported by Darwin.
/// Callers receive a URL and do not handle C buffers or proc_pidpath directly.
public struct DarwinProcessExecutableURLResolver: Resolver {
    private let maximumProcessPathLength = 4_096

    public init() {}

    public func resolveExecutableURL(
        for processIdentifier: Int32
    ) -> URL? {
        var path = [CChar](
            repeating: 0,
            count: maximumProcessPathLength
        )
        guard proc_pidpath(
            processIdentifier,
            &path,
            UInt32(path.count)
        ) > 0 else {
            return nil
        }
        return URL(fileURLWithPath: String(cString: path))
    }
}

/// Resolves the Unix owner of a process reported by Darwin. This keeps
/// libproc details out of privilege-policy code.
public struct DarwinProcessOwnerResolver: Resolver {
    public struct ProcessOwner: Sendable {
        public let userID: uid_t
        public let groupID: gid_t

        public init(userID: uid_t, groupID: gid_t) {
            self.userID = userID
            self.groupID = groupID
        }
    }

    public init() {}

    public func resolveOwner(for processIdentifier: Int32) -> ProcessOwner? {
        var information = proc_bsdinfo()
        let byteCount = proc_pidinfo(
            processIdentifier,
            PROC_PIDTBSDINFO,
            0,
            &information,
            Int32(MemoryLayout<proc_bsdinfo>.size)
        )
        guard byteCount == MemoryLayout<proc_bsdinfo>.size else { return nil }
        return ProcessOwner(userID: information.pbi_uid, groupID: information.pbi_gid)
    }
}
