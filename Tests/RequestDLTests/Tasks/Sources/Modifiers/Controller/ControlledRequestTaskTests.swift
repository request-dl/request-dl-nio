//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

/// End-to-end coverage of `.controller(_:)` through the public API, against a real
/// ``TransferServer`` on each executor: what the server's kernel actually accepted is what tells a
/// suspension that held the connection from one that only stopped the reader.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct ControlledRequestTaskTests {

    /// Far past the client's socket buffers and CFNetwork's read-ahead combined, so a transfer
    /// that stalls well short of it can only have been stopped by the suspension.
    private static let largeBody = 64 * 1_048_576

    private enum Executor: Sendable, CaseIterable, CustomTestStringConvertible {
        #if canImport(NIOCore)
        case nio
        #endif

        #if canImport(Darwin)
        case urlSession
        #endif

        var testDescription: String {
            switch self {
            #if canImport(NIOCore)
            case .nio:
                return "nio"
            #endif
            #if canImport(Darwin)
            case .urlSession:
                return "urlSession"
            #endif
            }
        }

        var session: Session {
            switch self {
            #if canImport(NIOCore)
            case .nio:
                return Session().requiredExecutor(.nio)
            #endif
            #if canImport(Darwin)
            case .urlSession:
                return Session().requiredExecutor(.urlSession)
            #endif
            }
        }
    }

    // MARK: - Tests

    /// The core guarantee, through the public API: suspended mid-body, the server can't get
    /// another byte out for as long as the controller stays suspended, and resuming carries on to
    /// an intact, complete body.
    @Test(arguments: Executor.allCases)
    private func suspendMidBody_holdsTheConnectionUntilResumed(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { server in
            // Given
            let controller = RequestController()
            let received = LockedValueBox(0)

            let result = try await DownloadTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Path("/resource")
                executor.session
            }
            .controller(controller)
            .result()

            let reader = _Concurrency.Task {
                for try await chunk in result.payload {
                    received.withLockedValue { $0 += chunk.count }
                }
            }

            try await eventually(timeout: 30) { received.withLockedValue { $0 } >= 4 * 1_048_576 }

            // When
            controller.suspend()

            let stalledAt = try await server.settled { server.bodyBytesWritten }

            // Then: stalled far short of the body, and staying there.
            #expect(stalledAt < Self.largeBody / 2)
            #expect(controller.isSuspended)

            try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)

            #expect(server.bodyBytesWritten == stalledAt)

            // When
            controller.resume()
            try await reader.value

            // Then
            #expect(received.withLockedValue { $0 } == Self.largeBody)
            #expect(server.acceptedConnections == 1)
        }
    }

    /// Sticky state: a request that starts while the controller is suspended starts suspended, so
    /// there's no window between creating the task and pausing it. Placed after `.map` on purpose:
    /// the controller reaches the transfer whatever sits in front of it in the chain.
    @Test(arguments: Executor.allCases)
    private func startedWhileSuspended_holdsTheBodyFromTheStart(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { server in
            // Given
            let controller = RequestController()
            controller.suspend()

            let task = DataTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Path("/resource")
                executor.session
            }
            .extractPayload()
            .map(\.count)
            .controller(controller)

            // When
            let running = _Concurrency.Task { try await task.result() }

            // Waits for the transfer to have really started: what follows only means something
            // if the connection was open and then held, not if it never got going.
            try await eventually(timeout: 30) { server.bodyBytesWritten > 0 }

            let stalledAt = try await server.settled { server.bodyBytesWritten }

            // Then
            #expect(stalledAt < Self.largeBody / 2)

            // When
            controller.resume()

            // Then
            #expect(try await running.value == Self.largeBody)
        }
    }

    /// One controller, several executions: `suspend()` pauses all of them.
    @Test(arguments: Executor.allCases)
    private func oneController_pausesEveryAttachedExecution(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { first in
            try await withTransferServer(.init(length: Self.largeBody)) { second in
                // Given
                let controller = RequestController()
                controller.suspend()

                func task(_ server: TransferServer) -> AnyTask<Int> {
                    DataTask {
                        BaseURL(.http, host: "127.0.0.1:\(server.port)")
                        Path("/resource")
                        executor.session
                    }
                    .extractPayload()
                    .map(\.count)
                    .controller(controller)
                }

                // When
                let firstRunning = _Concurrency.Task { try await task(first).result() }
                let secondRunning = _Concurrency.Task { try await task(second).result() }

                try await eventually(timeout: 30) { first.bodyBytesWritten > 0 && second.bodyBytesWritten > 0 }

                let firstStalledAt = try await first.settled { first.bodyBytesWritten }
                let secondStalledAt = try await second.settled { second.bodyBytesWritten }

                // Then
                #expect(firstStalledAt < Self.largeBody / 2)
                #expect(secondStalledAt < Self.largeBody / 2)

                // When
                controller.resume()

                // Then
                #expect(try await firstRunning.value == Self.largeBody)
                #expect(try await secondRunning.value == Self.largeBody)
            }
        }
    }

    /// Cancelling the `Task` ends a suspension: the controller never has to resume for a
    /// cancelled request to finish.
    @Test(arguments: Executor.allCases)
    private func cancellingWhileSuspended_endsTheRequest(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { server in
            // Given
            let controller = RequestController()
            controller.suspend()

            let running = _Concurrency.Task {
                try await DataTask {
                    BaseURL(.http, host: "127.0.0.1:\(server.port)")
                    Path("/resource")
                    executor.session
                }
                .controller(controller)
                .result()
            }

            // The transfer really started, so what's cancelled below is a live, suspended one and
            // not a request that failed before it began.
            try await eventually(timeout: 30) { server.bodyBytesWritten > 0 }
            _ = try await server.settled { server.bodyBytesWritten }

            // When
            running.cancel()

            // Then: ends (with an error), and never by hanging on the suspension.
            await #expect(throws: (any Error).self) {
                try await running.value
            }
        }
    }
}
