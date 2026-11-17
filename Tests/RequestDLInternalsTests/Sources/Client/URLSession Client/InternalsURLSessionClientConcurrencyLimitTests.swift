//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore) && canImport(Darwin)

import Foundation
import Testing

@_spi(Testing) @testable import RequestDLInternals
@testable import RequestDLTestSupport

/// The `.urlSession` counterpart of `InternalsClientConcurrencyLimitTests`, which covers `.nio`.
struct InternalsURLSessionClientConcurrencyLimitTests {

    /// A request that is cancelled while it waits for a slot is over: it must not stay queued behind
    /// requests that can be in flight for as long as the server cares to keep them, nor take a slot when
    /// its turn comes.
    @Test
    func execute_whenCancelledWhileWaitingForASlot_throwsAtOnceAndKeepsTheSlotsIntact() async throws {
        try await withHangingTCPServer { port in
            // Given: a limit of one, and a request holding it.
            let client = try Internals.URLSessionClient(
                configuration: .ephemeral,
                maximumConcurrentConnections: 1
            )

            let semaphore = try #require(client.connectionSemaphoreForTesting)
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/"))

            let holder = _Concurrency.Task {
                try await client.execute(request: URLRequest(url: url))
            }

            // Polled: the holder takes its slot from its own task.
            for _ in 0..<30_000 where semaphore.availablePermits > 0 {
                try await _Concurrency.Task.sleep(nanoseconds: 1_000_000)
            }

            try #require(semaphore.availablePermits == 0)

            // And a second one, queued behind it.
            let queued = _Concurrency.Task {
                try await client.execute(request: URLRequest(url: url))
            }

            try await semaphore.waitForWaiters(1, timeout: 30)

            // When
            queued.cancel()

            // Then: it leaves the queue without the holder having had to finish.
            try await semaphore.waitForWaiters(0, timeout: 30)

            await #expect(throws: CancellationError.self) {
                _ = try await queued.value
            }

            #expect(semaphore.availablePermits == 0)
            #expect(client.isRunning)

            // And the holder's slot is still the only one, and comes back when the holder is done.
            holder.cancel()
            _ = await holder.result

            #expect(semaphore.availablePermits == 1)
            #expect(!client.isRunning)
        }
    }
}

#endif
