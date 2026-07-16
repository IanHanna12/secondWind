import AppKit
import SecondWindCore

/// Uses the Finder-equivalent macOS recycle operation. Unlike a low-level
/// filesystem move, this lets macOS present any required authorization and
/// places the item in the current user's Finder Trash.
public struct FinderTrashMover: TrashMoving {
    public init() {}

    public func moveToTrash(_ url: URL) async throws {
        do {
            _ = try await NSWorkspace.shared.recycle([url])
        } catch {
            guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier,
                  url.standardizedFileURL.deletingLastPathComponent() == URL(fileURLWithPath: "/Applications").standardizedFileURL,
                  url.pathExtension == "app" else {
                throw error
            }
            _ = try await XPCPrivilegedApplicationTrashClient()
                .moveApplicationToTrash(at: url, bundleIdentifier: bundleIdentifier)
        }
    }
}
