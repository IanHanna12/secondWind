import Foundation

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
    public let inspection: ApplicationRemovalInspection

    public var exactRemnants: [AppRemnant] { remnants.filter(\.isExactKnownRemnant) }
    public var protectedRemnants: [AppRemnant] { remnants.filter { !$0.isExactKnownRemnant } }
    public var exactRemnantBytes: Int64 { exactRemnants.reduce(0) { $0 + $1.byteSize } }
    public var removableBytes: Int64 { applicationBytes + exactRemnantBytes }
}

public enum ApplicationMoveAuthorization: Sendable {
    case standardUserMove
    case privilegedTrashMove
    case unavailable(reason: String)

    public var description: String {
        switch self {
        case .standardUserMove: return "Normal user move"
        case .privilegedTrashMove: return "Administrator-authorized move to Trash"
        case .unavailable(let reason): return reason
        }
    }
}

/// Local, read-only information used to explain how an app can be moved. It
/// does not change the app or attempt authorization.
public struct ApplicationRemovalInspection: Sendable {
    public let path: String
    public let owner: String
    public let permissions: String
    public let hasExtendedACL: Bool
    public let protectionStatus: String
    public let moveAuthorization: ApplicationMoveAuthorization
}
