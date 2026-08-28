//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import NIOPosix
@_spi(Testing) import SwiftAsyncStream
import SwiftAsyncTesting
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsClientConcurrencyLimitTests {

    @Test
    func execute_whenMaximumConcurrentConnectionsSet_limitsInFlightRequests() async throws {
        try await withHangingServer { port in
            let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)
            let client = Internals.Client(
                eventLoopGroupProvider: .shared(group),
                configuration: .init(),
                maximumConcurrentConnections: 2
            )

            let startedCounter = StartedCounter()
            let requestCount = 5
            let releaseSignal = AsyncSignal()

            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                for _ in 0..<requestCount {
                    taskGroup.addTask {
                        let request = try HTTPClient.Request(url: "http://127.0.0.1:\(port)/")
                        let task = await client.execute(request: request, logger: nil)
                        await startedCounter.increment()

                        // Holds the permit until the assertion below has observed the queue,
                        // then releases it the same way `InternalsUnsafeTaskTests` does: cancel
                        // the awaiting task, which drives `UnsafeTask`'s cancel path and, with
                        // it, the semaphore signal.
                        let responseTask = _Concurrency.Task { try? await task.response() }
                        try? await releaseSignal.wait()
                        responseTask.cancel()
                        _ = await responseTask.value
                    }
                }

                // Deterministic rather than sleep-based: waits until exactly
                // `requestCount - 2` requests are queued behind the semaphore, which can only
                // happen once the other 2 have already acquired a permit — i.e. once the
                // concurrency limit is actually in effect, not after a guessed wall-clock
                // delay that a loaded CI runner can blow through.
                try await client.connectionSemaphore?.waitForWaiters(requestCount - 2, timeout: 5)

                // Then: only as many requests as the configured limit have actually acquired a
                // permit; the rest are still queued on the semaphore.
                #expect(client.connectionSemaphore?.waitingCount == requestCount - 2)
                #expect(client.connectionSemaphore?.availablePermits == 0)

                releaseSignal.signal()
                try await taskGroup.waitForAll()
            }

            // Then: every request eventually got its turn once earlier ones released theirs.
            #expect(await startedCounter.value == requestCount)

            _ = try? await client.shutdown()
            try await group.shutdownGracefully()
        }
    }
}

private actor StartedCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
