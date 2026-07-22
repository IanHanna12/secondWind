import Foundation

/// Broad semantic bases. They describe what a concrete type specializes and
/// intentionally do not introduce shared implementation or lifecycle.
public protocol Store: Sendable {}
public protocol Policy: Sendable {}
public protocol Builder: Sendable {}
public protocol Scanning: Sendable {}
public protocol Validator: Sendable {}
public protocol Verifier: Sendable {}
public protocol Resolver: Sendable {}
public protocol Reader: Sendable {}
public protocol Mover: Sendable {}
public protocol Discoverer: Sendable {}
