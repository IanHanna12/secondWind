import Darwin
import Foundation

/// Resolves a process identifier to the executable path reported by Darwin.
/// This is infrastructure: callers receive a `URL` and do not handle C path
/// buffers or `proc_pidpath` directly.
public struct DarwinProcessExecutableURLResolver: Sendable {
    private let maximumProcessPathLength = 4_096

    public init() {}

    public func resolveExecutableURL(for processIdentifier: Int32) -> URL? {
        var path = [CChar](repeating: 0, count: maximumProcessPathLength)
        guard proc_pidpath(processIdentifier, &path, UInt32(path.count)) > 0 else { return nil }
        return URL(fileURLWithPath: String(cString: path))
    }
}
