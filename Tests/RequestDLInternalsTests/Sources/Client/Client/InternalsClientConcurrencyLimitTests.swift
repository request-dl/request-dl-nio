//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import NIOPosix
import Testing

@testable import RequestDLInternals

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

            try await withThrowingTaskGroup(of: Void.self) { taskGroup in
                for _ in 0..<requestCount {
                    taskGroup.addTask {
                        let request = try HTTPClient.Request(url: "http://127.0.0.1:\(port)/")
                        let task = await client.execute(request: request, logger: nil)
                        await startedCounter.increment()

                        // Holds the permit long enough for the assertion below to observe it,
                        // then releases it the same way `InternalsUnsafeTaskTests` does: cancel
                        // the awaiting task, which drives `UnsafeTask`'s cancel path and, with
                        // it, the semaphore signal.
                        let responseTask = _Concurrency.Task { try? await task.response() }
                        try? await _Concurrency.Task.sleep(nanoseconds: 400_000_000)
                        responseTask.cancel()
                        _ = await responseTask.value
                    }
                }

                // Long enough for the first wave to acquire its permits, short enough that the
                // second wave — gated behind the 400ms hold above — has not started yet.
                try await _Concurrency.Task.sleep(nanoseconds: 150_000_000)

                // Then: only as many requests as the configured limit have actually reached
                // `_client.execute`; the rest are still suspended on the semaphore.
                #expect(await startedCounter.value == 2)

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
