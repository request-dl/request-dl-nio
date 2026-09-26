//
// See LICENSE for this package's licensing information.
//

import Testing

@_spi(Testing) @testable import RequestDLInternals

struct InternalsThrottledExecutorTests {

    @Test
    func acquire_whenUnlimited_neverBlocks() async throws {
        // Given
        let throttledExecutor = Internals.ThrottledExecutor(maximumConcurrentConnections: nil)

        // When / Then
        let release = await throttledExecutor.acquire()
        release()
    }

    /// `maximumConcurrentConnections` reaches this unvalidated from
    /// `Session.maximumConcurrentConnections(_:)` and from `Configured`'s config-file reader. A
    /// zero-permit semaphore can never be acquired, so every request through the session would
    /// wait forever: a non-positive limit is treated as "no limit" instead.
    @Test
    func acquire_whenLimitIsZero_isTreatedAsUnlimited() async throws {
        // Given
        let throttledExecutor = Internals.ThrottledExecutor(maximumConcurrentConnections: 0)

        // Then
        // `#require`, not `#expect`: a zero-permit semaphore would hang `acquire()` below forever.
        try #require(throttledExecutor.semaphoreForTesting == nil)

        let release = await throttledExecutor.acquire()
        release()
    }

    /// `AsyncSemaphore.init(permits:)` preconditions on a non-negative count, which traps even
    /// in release builds: a negative limit used to crash the process the first time a client
    /// was built for the session.
    @Test
    func acquire_whenLimitIsNegative_isTreatedAsUnlimitedInsteadOfTrapping() async throws {
        // Given
        let throttledExecutor = Internals.ThrottledExecutor(maximumConcurrentConnections: -1)

        // Then
        // `#require`, not `#expect`: a zero-permit semaphore would hang `acquire()` below forever.
        try #require(throttledExecutor.semaphoreForTesting == nil)

        let release = await throttledExecutor.acquire()
        release()
    }

    /// Mirrors `InternalsClientConcurrencyLimitTests`, but against the hoisted throttling logic
    /// directly rather than through `Internals.Client`, the wrapper any future concrete client
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
