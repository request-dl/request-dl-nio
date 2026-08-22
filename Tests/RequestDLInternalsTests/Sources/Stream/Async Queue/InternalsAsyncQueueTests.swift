//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDLInternals

private final class Box<Value: Sendable>: @unchecked Sendable {

    private let lock = Lock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock { body(&value) }
    }
}

struct InternalsAsyncQueueTests {

    @Test
    func asyncQueue_whenOperationsAreSubmitted_shouldRunThemInSubmissionOrder() async {
        // Given
        let queue = Internals.AsyncQueue()
        let order = Box<[Int]>([])

        // When
        for index in 0..<5 {
            queue.addOperation {
                order.withLock { $0.append(index) }
            }
        }

        await queue.waitUntilIdle()

        // Then
        #expect(order.withLock { $0 } == Array(0..<5))
    }

    @Test
    func asyncQueue_whenIdle_shouldReturnImmediately() async {
        // Given
        let queue = Internals.AsyncQueue()

        // Then
        await queue.waitUntilIdle()
    }

    @Test
    func asyncQueue_whenSubmittedAgainDuringADrain_shouldWaitForTheNewEpochToo() async {
        // Given
        let queue = Internals.AsyncQueue()
        let secondRan = Box(false)

        // When
        queue.addOperation {
            queue.addOperation {
                secondRan.withLock { $0 = true }
            }
        }

        await queue.waitUntilIdle()

        // Then
        #expect(secondRan.withLock { $0 })
    }

    @Test
    func asyncQueue_whenCallingTaskIsCancelled_shouldReturnWithoutJoiningCurrentEpoch() async throws {
        // Given
        let queue = Internals.AsyncQueue()
        let started = AsyncSignal()
        let release = AsyncSignal()
        let finished = Box(false)

        // A queue that stays busy until the test explicitly lets it finish, so `waitUntilIdle`
        // has a real epoch to join (and, before the fix, to spin against) instead of returning
        // immediately because the queue was already idle.
        queue.addOperation {
            started.signal()
            try? await release.wait()
        }

        try await started.wait()

        let waiter = _Concurrency.Task {
            await queue.waitUntilIdle()
        }
        waiter.cancel()

        // Observed from an unstructured task instead of awaited directly: a regression back to
        // the old `try?`-only loop leaves `waiter` spinning until `release` is signalled below,
        // and polling a flag lets that be reported as a failure below rather than hanging the
        // suite the way joining `waiter` (directly or through `withTaskGroup`) would.
        _Concurrency.Task {
            await waiter.value
            finished.withLock { $0 = true }
        }

        // Then: returns promptly instead of spinning until `release` is signalled.
        var returnedPromptly = false

        for _ in 0..<200 {
            if finished.withLock({ $0 }) {
                returnedPromptly = true
                break
            }
            try? await _Concurrency.Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(returnedPromptly)

        // Cleanup: let the blocked operation finish and drain the queue for real, and give the
        // stray `waiter` (still spinning above if the assertion just failed) a chance to settle.
        release.signal()
        await queue.waitUntilIdle()
    }
}
