//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsThrottledExecutorTests {

    @Test
    func acquire_whenUnlimited_neverBlocks() async throws {
        // Given
        let throttledExecutor = Internals.ThrottledExecutor(maximumConcurrentConnections: nil)

        // When / Then
        let release = await throttledExecutor.acquire()
        release()
    }

    /// Mirrors `InternalsClientConcurrencyLimitTests`, but against the hoisted throttling logic
    /// directly rather than through `Internals.Client` -- the wrapper any future concrete client
    /// shares this gating behavior through.
    @Test
    func acquire_whenLimited_gatesConcurrentAcquisitions() async throws {
        // Given
        let throttledExecutor = Internals.ThrottledExecutor(maximumConcurrentConnections: 2)
        let startedCounter = StartedCounter()
        let operationCount = 5

        try await withThrowingTaskGroup(of: Void.self) { taskGroup in
            for _ in 0..<operationCount {
                taskGroup.addTask {
                    let release = await throttledExecutor.acquire()
                    await startedCounter.increment()

                    try? await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
                    release()
                }
            }

            // Long enough for the first wave to acquire its permits, short enough that the
            // second wave has not started yet.
            try await _Concurrency.Task.sleep(nanoseconds: 75_000_000)

            // Then: only as many operations as the configured limit have actually started; the
            // rest are still suspended in `acquire()`.
            #expect(await startedCounter.value == 2)

            try await taskGroup.waitForAll()
        }

        // Then: every operation eventually got its turn once earlier ones released theirs.
        #expect(await startedCounter.value == operationCount)
    }
}

private actor StartedCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
