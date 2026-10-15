//
// See LICENSE for this package's licensing information.
//

import Dispatch
import Logging
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// `Timeout(_:for: .read)` is how long a request may go without a byte moving, enforced by
/// RequestDL itself, so the same on every executor and not counting what the application holds
/// back. Each of these runs against a real ``TransferServer`` on every executor.
///
/// The time is not the machine's. Each request counts a ``FakeIdleClock`` the test moves, so what
/// runs out, and when, is exactly what the test says: a test that waited for real seconds to pass
/// would fail whenever the machine stalled for as long, which a loaded one does.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct ReadTimeoutTests {

    private static let largeBody = 64 * 1_048_576
    private static let uploadSize = 24 * 1_048_576

    /// The budget every test gives a request, in the fake clock's time.
    private static let budget = UnitTime.seconds(60)

    private typealias Executor = TransferTestExecutor

    private static func uploadBody() -> Data {
        var data = Data()
        data.reserveCapacity(uploadSize)

        var position = 0
        while position < uploadSize {
            let count = min(65_536, uploadSize - position)
            data.append(contentsOf: TransferServer.uploadBody(from: position, count: count))
            position += count
        }

        return data
    }

    // MARK: - Silence

    /// A server that stops sending mid-body fails the request, the same way on every executor.
    @Test(arguments: Executor.allCases)
    private func aServerThatGoesSilent_failsWithReadTimeoutError(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { server in
            // Given
            let clock = FakeIdleClock()
            server.holdsDownloadAt = 2 * 1_048_576
            defer { server.holdsDownloadAt = nil }

            let running = Running(clock) {
                _ = try await DataTask {
                    BaseURL(.http, host: "127.0.0.1:\(server.port)")
                    Path("/resource")
                    executor.pinnedSession
                    Timeout(Self.budget, for: .read)
                }
                .result()
            }

            try await eventually(timeout: 60) { server.bodyBytesWritten >= 1_048_576 }

            // When: a whole budget goes by.
            await clock.advance(by: Self.budget.nanoseconds, until: { running.isDone })

            // Then
            #expect(await running.error is ReadTimeoutError)
        }
    }

    /// A head with no body behind it is silence too: the budget starts over with the head, and runs
    /// out when nothing follows it.
    @Test(arguments: Executor.allCases)
    private func aServerThatSendsTheHeadAndNothingElse_failsWithReadTimeoutError(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { server in
            // Given
            let clock = FakeIdleClock()
            server.holdsDownloadAt = 0
            defer { server.holdsDownloadAt = nil }

            let running = Running(clock) {
                _ = try await DataTask {
                    BaseURL(.http, host: "127.0.0.1:\(server.port)")
                    Path("/resource")
                    executor.pinnedSession
                    Timeout(Self.budget, for: .read)
                }
                .result()
            }

            try await eventually(timeout: 60) { server.acceptedConnections >= 1 }

            // When
            await clock.advance(by: Self.budget.nanoseconds, until: { running.isDone })

            // Then
            #expect(await running.error is ReadTimeoutError)
        }
    }

    // MARK: - What the application holds back

    /// Time the application spent holding the transfer still is not time the server was silent.
    @Test(arguments: Executor.allCases)
    private func aSuspensionLongerThanTheBudget_doesNotCount(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { server in
            // Given
            let clock = FakeIdleClock()
            let controller = RequestController()
            let received = LockedValueBox(0)

            let running = Running(clock) {
                let result = try await DownloadTask {
                    BaseURL(.http, host: "127.0.0.1:\(server.port)")
                    Path("/resource")
                    executor.pinnedSession
                    Timeout(Self.budget, for: .read)
                }
                .controller(controller)
                .result()

                for try await chunk in result.payload {
                    received.withLockedValue { $0 += chunk.count }
                }
            }

            try await eventually(timeout: 60) { received.withLockedValue { $0 } >= 4 * 1_048_576 }

            // When: five budgets, with the transfer suspended.
            controller.suspend()

            for _ in 0..<5 {
                #expect(await clock.advance(by: Self.budget.nanoseconds))
            }

            // Then
            #expect(!running.isDone)

            controller.resume()
            #expect(await running.error == nil)
            #expect(received.withLockedValue { $0 } == Self.largeBody)
        }
    }

    /// A body nobody has read yet is not a server gone quiet: the transfer waits for its reader.
    @Test(arguments: Executor.allCases)
    private func aSlowReader_doesNotCount(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { server in
            // Given: a reader that takes its first chunk and then waits to be told to go on.
            let clock = FakeIdleClock()
            let received = LockedValueBox(0)
            let isReleased = LockedValueBox(false)

            let running = Running(clock) {
                let result = try await DownloadTask {
                    BaseURL(.http, host: "127.0.0.1:\(server.port)")
                    Path("/resource")
                    executor.pinnedSession
                    Timeout(Self.budget, for: .read)
                }
                .result()

                var isFirst = true

                for try await chunk in result.payload {
                    if isFirst {
                        isFirst = false

                        while !isReleased.withLockedValue({ $0 }) {
                            try await _Concurrency.Task.sleep(nanoseconds: 5_000_000)
                        }
                    }

                    received.withLockedValue { $0 += chunk.count }
                }
            }

            // The transfer fills the window ahead of the reader and waits there: the server can
            // write no more.
            let stalledAt = try await server.settled { server.bodyBytesWritten }
            #expect(stalledAt < Self.largeBody / 2)

            // When: five budgets, with nobody reading.
            for _ in 0..<5 {
                #expect(await clock.advance(by: Self.budget.nanoseconds))
            }

            // Then
            #expect(!running.isDone)

            isReleased.withLockedValue { $0 = true }
            #expect(await running.error == nil)
            #expect(received.withLockedValue { $0 } == Self.largeBody)
        }
    }

    // MARK: - No deadline, and a deadline that keeps starting over

    /// `.infinity` is no limit: no deadline is even made, so a server may stay silent for as long
    /// as it likes.
    @Test(arguments: Executor.allCases)
    private func infinity_buildsNoDeadlineAtAll(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: 4 * 1_048_576)) { server in
            // Given
            let clock = FakeIdleClock()
            server.holdsDownloadAt = 1_048_576

            let running = Running(clock) {
                try await DataTask {
                    BaseURL(.http, host: "127.0.0.1:\(server.port)")
                    Path("/resource")
                    executor.pinnedSession
                    Timeout(.infinity, for: .read)
                }
                .extractPayload()
                .map(\.count)
                .result()
            }

            // When: the server is silent, and nothing is counting.
            try await eventually(timeout: 60) { server.bodyBytesWritten >= 512 * 1_024 }
            clock.now.withLockedValue { $0 += 1_000 * UInt64(Self.budget.nanoseconds) }

            // Then
            #expect(clock.sleepCount == 0)
            #expect(!running.isDone)

            server.holdsDownloadAt = nil
            #expect(await running.value == 4 * 1_048_576)
        }
    }

    /// Bytes keep starting the budget over: a transfer that is slow but moving never fails, however
    /// long it takes in all.
    @Test(arguments: Executor.allCases)
    private func aTransferThatKeepsMoving_neverFails(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: 4 * 1_048_576)) { server in
            // Given
            let clock = FakeIdleClock()
            let received = LockedValueBox(0)
            server.holdsDownloadAt = 0

            let running = Running(clock) {
                let result = try await DownloadTask {
                    BaseURL(.http, host: "127.0.0.1:\(server.port)")
                    Path("/resource")
                    executor.pinnedSession
                    Timeout(Self.budget, for: .read)
                }
                .result()

                for try await chunk in result.payload {
                    received.withLockedValue { $0 += chunk.count }
                }
            }

            // When: a megabyte at a time, with just under a budget going by after each, so more
            // than the budget goes by in all but never the whole of it without a byte.
            for step in 1...3 {
                // The bytes of this step are what start the budget over, so they come in before
                // the time goes by, not after: bytes still on their way from the last step would
                // leave the budget counting from the one before.
                server.holdsDownloadAt = step * 1_048_576
                try await eventually(timeout: 60) { received.withLockedValue { $0 } >= step * 1_048_576 - 65_536 }

                await clock.advance(by: Self.budget.nanoseconds - 1_000_000_000)
            }

            // Then: nearly three budgets went by, and the transfer is none the worse for it.
            #expect(!running.isDone)

            server.holdsDownloadAt = nil
            #expect(await running.error == nil)
            #expect(received.withLockedValue { $0 } == 4 * 1_048_576)
        }
    }

    // MARK: - Uploads

    /// The request body going out counts as much as the response coming in: an upload whose
    /// server stops reading it is as silent as a download whose server stops sending.
    @Test(arguments: Executor.allCases)
    private func aServerThatStopsReadingAnUpload_failsWithReadTimeoutError(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: 1_024)) { server in
            // Given: the server's own thread stops reading once it has a little of the body, so
            // what the client can still write is only what its socket buffers take.
            let clock = FakeIdleClock()
            let gate = DispatchSemaphore(value: 0)

            // Waits for two minutes at most, so a test that fails does not leave a thread behind.
            server.uploadReadDelay = 2_000
            server.onUploadProgress = { received in
                guard received >= 262_144 else {
                    return
                }

                _ = gate.wait(timeout: .now() + 120)
                gate.signal()
            }

            let running = Running(clock) {
                _ = try await UploadTask {
                    BaseURL(.http, host: "127.0.0.1:\(server.port)")
                    Path("/upload")
                    RequestMethod(.put)
                    executor.pinnedSession
                    Timeout(Self.budget, for: .read)
                    Payload(data: Self.uploadBody())
                }
                .collectData()
                .extractPayload()
                .result()
            }

            try await eventually(timeout: 60) { server.uploadBytesReceived >= 262_144 }

            // When
            await clock.advance(by: Self.budget.nanoseconds, until: { running.isDone })

            // Then
            #expect(await running.error is ReadTimeoutError)
            gate.signal()
        }
    }

    /// An upload suspended for longer than the budget is not an upload the server stopped
    /// reading: it carries on from where it was, and the server gets every byte once, in order.
    @Test(arguments: Executor.allCases)
    private func aSuspendedUploadLongerThanTheBudget_doesNotCount(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: 1_024)) { server in
            // Given: suspended by the server's own thread at an exact byte, early in the body.
            let clock = FakeIdleClock()
            let controller = RequestController()
            let isSuspended = LockedValueBox(false)

            server.uploadReadDelay = 2_000
            server.onUploadProgress = { received in
                guard received >= 262_144, !isSuspended.withLockedValue({ $0 }) else {
                    return
                }

                isSuspended.withLockedValue { $0 = true }
                controller.suspend()
            }

            let running = Running(clock) {
                _ = try await UploadTask {
                    BaseURL(.http, host: "127.0.0.1:\(server.port)")
                    Path("/upload")
                    RequestMethod(.put)
                    executor.pinnedSession
                    Timeout(Self.budget, for: .read)
                    Payload(data: Self.uploadBody())
                }
                .collectData()
                .extractPayload()
                .controller(controller)
                .result()
            }

            try await eventually(timeout: 60) { isSuspended.withLockedValue { $0 } }
            server.onUploadProgress = nil

            // When: five budgets, with the upload suspended.
            for _ in 0..<5 {
                #expect(await clock.advance(by: Self.budget.nanoseconds))
            }

            // Then
            #expect(!running.isDone)

            controller.resume()
            #expect(await running.error == nil)
            try await eventually(timeout: 60) { !server.requests.isEmpty }

            let request = try #require(server.requests.first)
            #expect(request.bodyLength == Self.uploadSize)
            #expect(request.isBodyIntact)
            #expect(request.isBodyComplete)
        }
    }

    // MARK: - Connect

    #if canImport(Darwin)
    /// `URLSession` has no phase for connecting to limit, so a `Timeout` for `.connect` is said to
    /// do nothing there, and only once someone set it apart from `.read`.
    @Test(arguments: [(true, false), (false, true), (true, true)] as [(connect: Bool, read: Bool)])
    private func aConnectTimeoutOnURLSession_isSaidToDoNothing(_ isSet: (connect: Bool, read: Bool)) async throws {
        try await withTransferServer(.init(length: 1_024)) { server in
            // Given
            let messages = LockedValueBox<[String]>([])

            // When
            _ = try await Logger.withTesting(
                level: .warning,
                recorded: { record in
                    messages.withLockedValue { $0.append(String(describing: record.message)) }
                },
                perform: { logger in
                    try await DataTask {
                        BaseURL(.http, host: "127.0.0.1:\(server.port)")
                        Path("/resource")
                        Executor.urlSession.pinnedSession

                        if isSet.connect {
                            Timeout(.seconds(5), for: .connect)
                        }

                        if isSet.read {
                            Timeout(.seconds(7), for: .read)
                        }
                    }
                    .extractPayload()
                    .environment(\.logger, logger)
                    .result()
                }
            )

            // Then
            let said = messages.withLockedValue { $0 }.contains { $0.contains("Timeout(_:for: .connect)") }
            #expect(said == isSet.connect)
        }
    }

    /// `Timeout(_:for: .all)` sets both to the same value, and the part that applies is the one
    /// that was wanted: nothing to say.
    @Test
    private func aTimeoutForAll_saysNothing() async throws {
        try await withTransferServer(.init(length: 1_024)) { server in
            // Given
            let messages = LockedValueBox<[String]>([])

            // When
            _ = try await Logger.withTesting(
                level: .warning,
                recorded: { record in
                    messages.withLockedValue { $0.append(String(describing: record.message)) }
                },
                perform: { logger in
                    try await DataTask {
                        BaseURL(.http, host: "127.0.0.1:\(server.port)")
                        Path("/resource")
                        Executor.urlSession.pinnedSession
                        Timeout(.seconds(30))
                    }
                    .extractPayload()
                    .environment(\.logger, logger)
                    .result()
                }
            )

            // Then
            #expect(messages.withLockedValue { $0 }.allSatisfy { !$0.contains("Timeout(_:for: .connect)") })
        }
    }
    #endif
}

// MARK: - Helpers

/// A request running under a ``FakeIdleClock``, and how it ended.
private final class Running<Value: Sendable>: @unchecked Sendable {

    private let task: _Concurrency.Task<Result<Value, any Error>, Never>
    private let done: LockedValueBox<Bool>

    var isDone: Bool {
        done.withLockedValue { $0 }
    }

    /// The error it ended with, once it has.
    var error: (any Error)? {
        get async {
            if case .failure(let error) = await task.value {
                return error
            }

            return nil
        }
    }

    /// What it ended with, once it has.
    var value: Value? {
        get async {
            if case .success(let value) = await task.value {
                return value
            }

            return nil
        }
    }

    init(_ clock: FakeIdleClock, _ body: @escaping @Sendable () async throws -> Value) {
        let done = LockedValueBox(false)
        self.done = done

        task = _Concurrency.Task {
            let result: Result<Value, any Error>

            do {
                result = .success(try await clock.bind(body))
            } catch {
                result = .failure(error)
            }

            done.withLockedValue { $0 = true }
            return result
        }
    }
}
