import Foundation

/// Broad semantic bases. They describe what a concrete type specializes and
/// intentionally do not introduce shared implementation or lifecycle.
public protocol Store: Sendable {}
public protocol Policy: Sendable {}
public protocol Builder: Sendable {}
public protocol Inventory: Sendable {}
public protocol Report: Sendable {}
public protocol Summary: Sendable {}
public protocol Outcome: Sendable {}
public protocol Service: Sendable {}
public protocol Runner: Sendable {}
public protocol Renderer: Sendable {}
public protocol Scanning: Sendable {}
public protocol Validator: Sendable {}
public protocol Verifier: Sendable {}
public protocol Resolver: Sendable {}
public protocol Reader: Sendable {}
public protocol Mover: Sendable {}
public protocol Discoverer: Sendable {}

/// An immutable observation captured at one point in time.
/// Concrete snapshot families may add persistence or schema requirements.
public protocol Snapshot: Sendable {
    var capturedAt: Date { get }
}

/// Produces a friendly label for a real local path without changing that path.
/// Apple's `.noindex` suffix remains part of storage and restore identities.
public enum LocalPathDisplay {
    public static func name(for path: String) -> String {
        name(for: URL(fileURLWithPath: path))
    }

    public static func name(for url: URL) -> String {
        guard url.pathExtension == "noindex" else {
            return url.lastPathComponent
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

public extension JSONEncoder {
    static var secondWind: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

public extension JSONDecoder {
    static var secondWind: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
