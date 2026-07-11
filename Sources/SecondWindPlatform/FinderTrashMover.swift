import Foundation
import SecondWindCore

/// macOS implementation of the application's Finder Trash port.
public struct FinderTrashMover: TrashMoving {
    public init() {}

    public func moveToTrash(_ url: URL) throws {
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
    }
}
