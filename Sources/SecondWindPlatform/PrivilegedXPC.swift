import Foundation
import SecondWindCore

/// The only XPC interface exposed by the optional root helper. It transfers a
/// typed request and typed result; it intentionally has no command, argument,
/// path, or shell-text parameter.
@objc public protocol PrivilegedMaintenanceXPC {
    func perform(_ requestData: Data, withReply reply: @escaping (Data?, NSError?) -> Void)
}

public struct PrivilegedMaintenanceReply: Codable, Sendable {
    public let task: MaintenanceTask
    public let succeeded: Bool
    public let output: String

    public init(task: MaintenanceTask, succeeded: Bool, output: String) {
        self.task = task
        self.succeeded = succeeded
        self.output = output
    }
}

public enum PrivilegedMaintenanceClientError: LocalizedError, Sendable {
    case unavailable
    case malformedReply
    case emptyReply
    case connectionInterrupted

    public var errorDescription: String? {
        switch self {
        case .unavailable: return "The optional privileged helper is unavailable or disabled."
        case .malformedReply: return "The privileged helper returned an invalid response."
        case .emptyReply: return "The privileged helper finished without a response."
        case .connectionInterrupted: return "The privileged helper connection was interrupted."
        }
    }
}

/// App-side XPC client for an enabled, bundled helper. The connection is made
/// only after a user confirms a maintenance operation.
public final class XPCPrivilegedMaintenanceClient: @unchecked Sendable, PrivilegedMaintenanceClient {
    public static let serviceName = "org.secondwind.PrivilegedMaintenanceHelper"
    private let helperConnection: PrivilegedHelperConnection

    public convenience init(serviceName: String = XPCPrivilegedMaintenanceClient.serviceName) {
        self.init(serviceName: serviceName, transportFactory: { serviceName in
            NSXPCPrivilegedHelperTransport(serviceName: serviceName)
        })
    }

    /// Internal injection point for deterministic client tests. The public
    /// client continues to construct an NSXPC-backed transport.
    init(
        serviceName: String,
        transportFactory: @escaping @Sendable (String) -> any PrivilegedHelperTransport
    ) {
        self.helperConnection = PrivilegedHelperConnection {
            transportFactory(serviceName)
        }
    }

    public func run(_ request: PrivilegedMaintenanceRequest) async throws {
        _ = try await execute(request)
    }

    public func execute(_ request: PrivilegedMaintenanceRequest) async throws -> MaintenanceExecutionResult {
        let requestData = try JSONEncoder.secondWind.encode(request)
        let replyData = try await helperConnection.send(requestData)
        let reply: PrivilegedMaintenanceReply
        do {
            reply = try JSONDecoder.secondWind.decode(PrivilegedMaintenanceReply.self, from: replyData)
        } catch {
            throw PrivilegedMaintenanceClientError.malformedReply
        }
        guard reply.task == request.task else { throw PrivilegedMaintenanceClientError.malformedReply }
        return .init(task: reply.task, succeeded: reply.succeeded, output: reply.output)
    }
}

/// Internal boundary between the async client and NSXPC. Tests inject a fake
/// transport so they can deterministically deliver competing callbacks.
protocol PrivilegedHelperTransport: Sendable {
    func send(_ requestData: Data, reply: @escaping @Sendable (Result<Data, Error>) -> Void)
    func invalidate()
}

/// Owns the mechanics of one request to the root XPC helper: start a
/// transport, wait for one callback, and close it. Cancellation ends the
/// caller's wait; it does not attempt to stop an already-running helper task.
private struct PrivilegedHelperConnection: Sendable {
    private let transportFactory: @Sendable () -> any PrivilegedHelperTransport

    init(transportFactory: @escaping @Sendable () -> any PrivilegedHelperTransport) {
        self.transportFactory = transportFactory
    }

    func send(_ requestData: Data) async throws -> Data {
        let transport = transportFactory()
        let response = OneShotXPCResponse<Data>(invalidate: {
            transport.invalidate()
        })

        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                response.install(continuation)
                transport.send(requestData) { outcome in
                    response.finish(outcome)
                }
            }
        }, onCancel: {
            response.cancel()
        })
    }
}

/// NSXPC implementation of the transport boundary. Its sole job is to map
/// XPC callbacks into a single typed result; OneShotXPCResponse owns the
/// exactly-once and cancellation semantics.
private final class NSXPCPrivilegedHelperTransport: @unchecked Sendable, PrivilegedHelperTransport {
    private let serviceName: String
    private let lock = NSLock()
    private var connection: NSXPCConnection?
    private var invalidated = false

    init(serviceName: String) {
        self.serviceName = serviceName
    }

    func send(_ requestData: Data, reply: @escaping @Sendable (Result<Data, Error>) -> Void) {
        let newConnection = NSXPCConnection(machServiceName: serviceName, options: .privileged)
        newConnection.remoteObjectInterface = NSXPCInterface(with: PrivilegedMaintenanceXPC.self)
        newConnection.interruptionHandler = {
            reply(.failure(PrivilegedMaintenanceClientError.connectionInterrupted))
        }
        newConnection.invalidationHandler = {
            reply(.failure(PrivilegedMaintenanceClientError.unavailable))
        }

        guard retain(newConnection) else {
            newConnection.invalidate()
            return
        }

        newConnection.resume()
        guard isActive(newConnection) else { return }

        guard let helper = newConnection.remoteObjectProxyWithErrorHandler({ _ in
            reply(.failure(PrivilegedMaintenanceClientError.unavailable))
        }) as? PrivilegedMaintenanceXPC else {
            reply(.failure(PrivilegedMaintenanceClientError.unavailable))
            return
        }

        helper.perform(requestData) { replyData, error in
            if let error {
                reply(.failure(error))
            } else if let replyData {
                reply(.success(replyData))
            } else {
                reply(.failure(PrivilegedMaintenanceClientError.emptyReply))
            }
        }
    }

    func invalidate() {
        let activeConnection: NSXPCConnection?
        lock.lock()
        invalidated = true
        activeConnection = connection
        connection = nil
        lock.unlock()
        activeConnection?.invalidate()
    }

    private func retain(_ newConnection: NSXPCConnection) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !invalidated else { return false }
        connection = newConnection
        return true
    }

    private func isActive(_ expectedConnection: NSXPCConnection) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return !invalidated && connection === expectedConnection
    }
}

/// Owns the suspended `await` until exactly one outcome completes it. A
/// terminal event may occur before continuation installation when a task is
/// cancelled immediately; in that case the outcome is retained and delivered
/// as soon as installation occurs.
private final class OneShotXPCResponse<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingContinuation: CheckedContinuation<Value, Error>?
    private var terminalOutcome: Result<Value, Error>?
    private let invalidate: @Sendable () -> Void

    init(invalidate: @escaping @Sendable () -> Void) {
        self.invalidate = invalidate
    }

    func finish(_ outcome: Result<Value, Error>) {
        let waitingContinuation: CheckedContinuation<Value, Error>?

        lock.lock()
        guard terminalOutcome == nil else {
            lock.unlock()
            return
        }
        terminalOutcome = outcome
        waitingContinuation = pendingContinuation
        pendingContinuation = nil
        lock.unlock()

        invalidate()
        waitingContinuation?.resume(with: outcome)
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        let completedOutcome: Result<Value, Error>?

        lock.lock()
        precondition(pendingContinuation == nil, "A one-shot XPC response may install only one continuation.")
        completedOutcome = terminalOutcome
        if completedOutcome == nil {
            pendingContinuation = continuation
        }
        lock.unlock()

        if let completedOutcome {
            continuation.resume(with: completedOutcome)
        }
    }
}
