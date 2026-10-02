//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

/// `.controller(_:)` with a ``GroupTask``, on every executor: a controller reaches every request
/// of the group, whether it's attached to the group itself or to each request inside it.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct ControlledGroupTaskTests {

    private static let length = 32 * 1_048_576

    private static let requests = 3

    private typealias Executor = TransferTestExecutor

    private static func task(
        for server: TransferServer,
        executor: Executor
    ) -> AnyTask<Int> {
        DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path("/resource")
            executor.session
        }
        .extractPayload()
        .map(\.count)
        .eraseToAnyTask()
    }

    // MARK: - Tests

    /// One `.controller(_:)` on the group pauses every request in it, and resuming lets every one
    /// of them finish intact.
    @Test(arguments: Executor.allCases)
    private func controllerOnTheGroup_pausesEveryRequest(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            let controller = RequestController()
            controller.suspend()

            let group = GroupTask(Array(0..<Self.requests)) { _ in
                Self.task(for: server, executor: executor)
            }
            .controller(controller)

            // When
            let running = _Concurrency.Task { try await group.result() }

            try await eventually(timeout: 30) { server.acceptedConnections == Self.requests }
            let stalledAt = try await server.settled { server.bodyBytesWritten }

            // Then: every request is held well short of its body.
            #expect(stalledAt < Self.length * Self.requests / 2)

            try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
            #expect(server.bodyBytesWritten == stalledAt)

            // When
            controller.resume()
            let results = try await running.value

            // Then
            #expect(results.count == Self.requests)

            for index in 0..<Self.requests {
                #expect(try results[index]?.get() == Self.length)
            }
        }
    }

    /// A controller on each request inside the group, all the same one, does the same.
    @Test(arguments: Executor.allCases)
    private func controllerOnEachRequest_pausesEveryRequest(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            let controller = RequestController()
            controller.suspend()

            let group = GroupTask(Array(0..<Self.requests)) { _ in
                Self.task(for: server, executor: executor)
                    .controller(controller)
            }

            // When
            let running = _Concurrency.Task { try await group.result() }

            try await eventually(timeout: 30) { server.acceptedConnections == Self.requests }
            let stalledAt = try await server.settled { server.bodyBytesWritten }

            // Then
            #expect(stalledAt < Self.length * Self.requests / 2)

            // When
            controller.resume()
            let results = try await running.value

            // Then
            for index in 0..<Self.requests {
                #expect(try results[index]?.get() == Self.length)
            }
        }
    }

    /// Two controllers, one per half of the group: suspending one pauses only its requests.
    @Test(arguments: Executor.allCases)
    private func separateControllers_pauseOnlyTheirOwnRequests(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            let paused = RequestController()
            let running = RequestController()
            paused.suspend()

            let group = GroupTask([0, 1]) { index in
                Self.task(for: server, executor: executor)
                    .controller(index == 0 ? paused : running)
            }

            // When
            let result = _Concurrency.Task { try await group.result() }

            try await eventually(timeout: 30) { server.acceptedConnections == 2 }

            // Then: the free request's whole body goes out while the other is still held short of
            // its own, so what the server wrote is one body and a bit, never two.
            //
            // Waits for that whole body first: `settled` alone returns after a quiet half second,
            // which a slow start of the free request can produce before its body is out.
            try await eventually(timeout: 60) { server.bodyBytesWritten >= Self.length }
            let stalledAt = try await server.settled { server.bodyBytesWritten }

            #expect(stalledAt >= Self.length)
            #expect(stalledAt < Self.length + Self.length / 2)

            // When
            paused.resume()
            let results = try await result.value

            // Then
            #expect(try results[0]?.get() == Self.length)
            #expect(try results[1]?.get() == Self.length)
        }
    }
}
