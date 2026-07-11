import Foundation
import XCTest
@testable import SecondWindCore
@testable import SecondWindPlatform

final class PrivilegedMaintenanceContractTests: XCTestCase {
    private let request = PrivilegedMaintenanceRequest(task: .periodicScripts, volumeUUID: nil)

    func testHelperValidationAcceptsOnlyKnownLocalVolumeUUID() throws {
        let volumeID = UUID()
        let local = VolumeReference(url: URL(fileURLWithPath: "/Volumes/Test"), uuid: volumeID, isLocal: true)
        let remote = VolumeReference(url: URL(string: "smb://example.invalid/Test")!, uuid: volumeID, isLocal: false)
        let request = PrivilegedMaintenanceRequest(task: .rebuildSpotlightIndex, volumeUUID: volumeID)

        XCTAssertNoThrow(try HelperRequestValidator().validate(request, mountedVolumes: [local]))
        XCTAssertThrowsError(try HelperRequestValidator().validate(request, mountedVolumes: [remote]))
        XCTAssertThrowsError(try HelperRequestValidator().validate(.init(task: .verifyVolume, volumeUUID: UUID()), mountedVolumes: [local]))
    }

    func testRequestDecodingRejectsUnknownTaskInsteadOfAcceptingCommandText() {
        let data = Data("{\"task\":\"runAnything\",\"volumeUUID\":null}".utf8)
        XCTAssertThrowsError(try JSONDecoder.secondWind.decode(PrivilegedMaintenanceRequest.self, from: data))
    }

    func testReplyThenInvalidationReturnsReplyExactlyOnce() async throws {
        let started = expectation(description: "request started")
        let transport = FakeTransport(started: started)
        let client = makeClient(transport: transport)
        let work = Task { try await client.execute(request) }

        await fulfillment(of: [started], timeout: 1)
        transport.emit(.success(try replyData(task: .periodicScripts, succeeded: true)))
        transport.emit(.failure(PrivilegedMaintenanceClientError.unavailable))

        let result = try await work.value
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.task, .periodicScripts)
        XCTAssertEqual(transport.invalidationCount, 1)
    }

    func testInterruptionWinsOverLaterReply() async throws {
        let started = expectation(description: "request started")
        let transport = FakeTransport(started: started)
        let client = makeClient(transport: transport)
        let work = Task { try await client.execute(request) }

        await fulfillment(of: [started], timeout: 1)
        transport.emit(.failure(PrivilegedMaintenanceClientError.connectionInterrupted))
        transport.emit(.success(try replyData(task: .periodicScripts, succeeded: true)))

        do {
            _ = try await work.value
            XCTFail("The first terminal event should win.")
        } catch let error as PrivilegedMaintenanceClientError {
            XCTAssertEqual(error, .connectionInterrupted)
        }
        XCTAssertEqual(transport.invalidationCount, 1)
    }

    func testCancellationInvalidatesAndIgnoresLaterReply() async throws {
        let started = expectation(description: "request started")
        let invalidated = expectation(description: "transport invalidated")
        let transport = FakeTransport(started: started, invalidated: invalidated)
        let client = makeClient(transport: transport)
        let work = Task { try await client.execute(request) }

        await fulfillment(of: [started], timeout: 1)
        work.cancel()
        await fulfillment(of: [invalidated], timeout: 1)
        transport.emit(.success(try replyData(task: .periodicScripts, succeeded: true)))

        do {
            _ = try await work.value
            XCTFail("Cancellation should end the caller's wait.")
        } catch is CancellationError {
            // Expected: the helper result is deliberately ignored after cancel.
        }
        XCTAssertEqual(transport.invalidationCount, 1)
    }

    func testCancellationRacingWithReplyCompletesOnlyOnce() async throws {
        let started = expectation(description: "request started")
        let transport = FakeTransport(started: started)
        let client = makeClient(transport: transport)
        let work = Task { try await client.execute(request) }

        await fulfillment(of: [started], timeout: 1)
        let data = try replyData(task: .periodicScripts, succeeded: true)
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            if index == 0 {
                work.cancel()
            } else {
                transport.emit(.success(data))
            }
        }

        do {
            let result = try await work.value
            XCTAssertEqual(result.task, .periodicScripts)
        } catch is CancellationError {
            // Either racing event may win, but only one may complete the task.
        }
        XCTAssertEqual(transport.invalidationCount, 1)
    }

    func testMalformedAndMismatchedRepliesAreRejected() async throws {
        let malformedStarted = expectation(description: "malformed request started")
        let malformedTransport = FakeTransport(started: malformedStarted)
        let malformedWork = Task { try await makeClient(transport: malformedTransport).execute(request) }
        await fulfillment(of: [malformedStarted], timeout: 1)
        malformedTransport.emit(.success(Data("not JSON".utf8)))
        await assertMalformedReply(from: malformedWork)

        let mismatchStarted = expectation(description: "mismatched request started")
        let mismatchTransport = FakeTransport(started: mismatchStarted)
        let mismatchWork = Task { try await makeClient(transport: mismatchTransport).execute(request) }
        await fulfillment(of: [mismatchStarted], timeout: 1)
        mismatchTransport.emit(.success(try replyData(task: .verifyVolume, succeeded: true)))
        await assertMalformedReply(from: mismatchWork)
    }

    private func makeClient(transport: FakeTransport) -> XPCPrivilegedMaintenanceClient {
        XPCPrivilegedMaintenanceClient(serviceName: "test.helper") { _ in transport }
    }

    private func replyData(task: MaintenanceTask, succeeded: Bool) throws -> Data {
        let reply = PrivilegedMaintenanceReply(task: task, succeeded: succeeded, output: "done")
        return try JSONEncoder.secondWind.encode(reply)
    }

    private func assertMalformedReply(from work: Task<MaintenanceExecutionResult, Error>) async {
        do {
            _ = try await work.value
            XCTFail("The reply should be rejected.")
        } catch let error as PrivilegedMaintenanceClientError {
            XCTAssertEqual(error, .malformedReply)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private final class FakeTransport: @unchecked Sendable, PrivilegedHelperTransport {
    private let lock = NSLock()
    private let started: XCTestExpectation
    private let invalidated: XCTestExpectation?
    private var reply: (@Sendable (Result<Data, Error>) -> Void)?
    private var count = 0

    init(started: XCTestExpectation, invalidated: XCTestExpectation? = nil) {
        self.started = started
        self.invalidated = invalidated
    }

    func send(_ requestData: Data, reply: @escaping @Sendable (Result<Data, Error>) -> Void) {
        lock.lock()
        self.reply = reply
        lock.unlock()
        started.fulfill()
    }

    func invalidate() {
        lock.lock()
        count += 1
        lock.unlock()
        invalidated?.fulfill()
    }

    func emit(_ outcome: Result<Data, Error>) {
        lock.lock()
        let callback = reply
        lock.unlock()
        callback?(outcome)
    }

    var invalidationCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}
