import Foundation

/// Metadata read directly from an installed application bundle. Missing values
/// stay unavailable; Second Wind never estimates them.
public struct InstalledApplication: Identifiable, Hashable, Sendable {
    public let url: URL
    public let bundleIdentifier: String?
    public let displayName: String
    public let version: String?
    public let build: String?

    public var id: String { url.standardizedFileURL.path }

    public init(
        url: URL,
        bundleIdentifier: String?,
        displayName: String,
        version: String? = nil,
        build: String? = nil
    ) {
        self.url = url.standardizedFileURL
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.version = version
        self.build = build
    }
}
