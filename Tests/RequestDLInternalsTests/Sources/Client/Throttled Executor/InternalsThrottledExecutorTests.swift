//
// See LICENSE for this package's licensing information.
//

@_spi(Testing) import SwiftAsyncStream
import Testing

@_spi(Testing) @testable import RequestDLInternals
@testable import RequestDLTestSupport

struct InternalsThrottledExecutorTests {

    @Test
    func acquire_whenUnlimited_neverBlocks() async throws {
        // Given
        let throttledExecutor = Internals.ThrottledExecutor(maximumConcurrentConnections: nil)

        // When / Then
        let release = try await throttledExecutor.acquire()
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

        let release = try await throttledExecutor.acquire()
        release()
    }

    /// `AsyncCancellableSemaphore.init(permits:)` preconditions on a non-negative count, which traps even
    /// in release builds, so a negative limit must not reach it when the first client is built
    /// for the session.
    @Test
    func acquire_whenLimitIsNegative_isTreatedAsUnlimitedInsteadOfTrapping() async throws {
        // Given
        let throttledExecutor = Internals.ThrottledExecutor(maximumConcurrentConnections: -1)

        // Then
        // `#require`, not `#expect`: a zero-permit semaphore would hang `acquire()` below forever.
        try #require(throttledExecutor.semaphoreForTesting == nil)

        let release = try await throttledExecutor.acquire()
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
                    let release = try await throttledExecutor.acquire()
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

    // MARK: - Idle time

    /// The line for a slot is the session's own limit holding the request back, not a server that
    /// went quiet: the read timeout of the execution that waits does not count it, and counts again
    /// from the moment the request is admitted.
    @Test
    func acquire_whileQueued_doesNotCountAsIdle() async throws {
        // Given: the only slot taken, and an execution whose budget is a thousand nanoseconds.
        let budget: Int64 = 1_000
        let clock = FakeIdleClock()
        let deadline = clock.makeDeadline(nanoseconds: budget)
        let throttledExecutor = Internals.ThrottledExecutor(maximumConcurrentConnections: 1)
        let semaphore = try #require(throttledExecutor.semaphoreForTesting)
        let holder = try await throttledExecutor.acquire()

        deadline.start()

        let waiter = _Concurrency.Task {
            try await Internals.IdleDeadline.$queueing.withValue(deadline) {
                try await throttledExecutor.acquire()
            }
        }

        try await semaphore.waitForWaiters(1, timeout: 30)

        // When: several budgets go by in the line.
        for _ in 0..<4 {
            #expect(await clock.advance(by: budget))
        }

        // Then
        #expect(!deadline.isExpired)

        // And once admitted, the whole budget starts, and runs out like any other.
        holder()
        let release = try await waiter.value

        await clock.advance(by: budget - 1)
        #expect(!deadline.isExpired)

        await clock.advanceUntilDone(deadline, by: budget)
        #expect(deadline.isExpired)

        release()
    }

    /// A caller that leaves the line by being cancelled leaves the pause too: the deadline of an
    /// execution that goes on after it counts again.
    @Test
    func acquire_whenCancelledWhileQueued_endsThePause() async throws {
        // Given
        let budget: Int64 = 1_000
        let clock = FakeIdleClock()
        let deadline = clock.makeDeadline(nanoseconds: budget)
        let throttledExecutor = Internals.ThrottledExecutor(maximumConcurrentConnections: 1)
        let semaphore = try #require(throttledExecutor.semaphoreForTesting)
        let holder = try await throttledExecutor.acquire()

        deadline.start()

        let waiter = _Concurrency.Task {
            try await throttledExecutor.acquire(pausing: deadline)
        }

        try await semaphore.waitForWaiters(1, timeout: 30)
        #expect(await clock.advance(by: budget))

        // When
        waiter.cancel()
        try await semaphore.waitForWaiters(0, timeout: 30)
        _ = await waiter.result

        // Then: nothing is paused any more, so the budget runs out.
        await clock.advanceUntilDone(deadline, by: budget)
        #expect(deadline.isExpired)

        holder()
    }

    // MARK: - Cancellation

    /// A caller whose `Task` is cancelled while it waits for a slot has no use for one, and the slots
    /// are held by requests that can stay in flight for as long as the server cares to. Waiting its
    /// turn first, and only then noticing, kept it stuck behind them.
    @Test
    func acquire_whenCancelledWhileQueued_throwsWithoutWaitingForASlot() async throws {
        // Given: the only slot is taken, and one caller is queued behind it.
        let throttledExecutor = Internals.ThrottledExecutor(maximumConcurrentConnections: 1)
        let semaphore = try #require(throttledExecutor.semaphoreForTesting)
        let holder = try await throttledExecutor.acquire()

        let waiter = _Concurrency.Task { try await throttledExecutor.acquire() }
        try await semaphore.waitForWaiters(1, timeout: 30)

        // When
        waiter.cancel()

        // Then: it leaves the queue at once, with the slot still taken by the holder. Waited for rather than
        // simply awaited, so that a waiter stuck behind the holder fails this test instead of hanging it.
        try await semaphore.waitForWaiters(0, timeout: 30)

        await #expect(throws: CancellationError.self) {
            _ = try await waiter.value
        }

        #expect(semaphore.waitingCount == 0)
        #expect(semaphore.availablePermits == 0)

        // And nothing leaked: the holder's slot is the only one there is, and it comes back.
        holder()
        #expect(semaphore.availablePermits == 1)

        let next = try await throttledExecutor.acquire()
        #expect(semaphore.availablePermits == 0)
        next()
        #expect(semaphore.availablePermits == 1)
    }

    /// Cancelling one caller in the queue must not let a later one past an earlier one.
    @Test
    func acquire_whenAQueuedCallerIsCancelled_keepsTheOrderOfTheOthers() async throws {
        // Given: the slot taken, and A, B and C queued in that order.
        let throttledExecutor = Internals.ThrottledExecutor(maximumConcurrentConnections: 1)
        let semaphore = try #require(throttledExecutor.semaphoreForTesting)
        let holder = try await throttledExecutor.acquire()
        let order = Order()

        var callers = [_Concurrency.Task<Void, Error>]()

        for (index, name) in ["A", "B", "C"].enumerated() {
            callers.append(
                _Concurrency.Task {
                    let release = try await throttledExecutor.acquire()
                    await order.append(name)
                    release()
                }
            )

            // One at a time, so the arrival order is the one the test says it is.
            try await semaphore.waitForWaiters(index + 1, timeout: 30)
        }

        // When: B gives up, then the slot frees up.
        callers[1].cancel()
        try await semaphore.waitForWaiters(2, timeout: 30)

        await #expect(throws: CancellationError.self) {
            try await callers[1].value
        }

        holder()
        try await callers[0].value
        try await callers[2].value

        // Then
        #expect(await order.names == ["A", "C"])
        #expect(semaphore.availablePermits == 1)
        #expect(semaphore.waitingCount == 0)
    }

    /// Without cancellation, the queue is first in, first out.
    @Test
    func acquire_whenLimited_servesCallersInArrivalOrder() async throws {
        // Given
        let throttledExecutor = Internals.ThrottledExecutor(maximumConcurrentConnections: 1)
        let semaphore = try #require(throttledExecutor.semaphoreForTesting)
        let holder = try await throttledExecutor.acquire()
        let order = Order()

        var callers = [_Concurrency.Task<Void, Error>]()

        for index in 0..<5 {
            callers.append(
                _Concurrency.Task {
                    let release = try await throttledExecutor.acquire()
                    await order.append(String(index))
                    release()
                }
            )

            try await semaphore.waitForWaiters(index + 1, timeout: 30)
        }

        // When
        holder()

        for caller in callers {
            try await caller.value
        }

        // Then
        #expect(await order.names == ["0", "1", "2", "3", "4"])
    }
}

private actor Order {
    private(set) var names = [String]()

    func append(_ name: String) {
        names.append(name)
    }
}

private actor StartedCounter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}
