import Darwin

/// Resolves the Unix owner of a process reported by Darwin. This keeps
/// libproc details out of privilege-policy code.
public struct DarwinProcessOwnerResolver: Sendable {
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
