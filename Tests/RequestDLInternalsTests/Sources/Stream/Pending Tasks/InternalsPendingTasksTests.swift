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

struct InternalsPendingTasksTests {

    @Test
    func pendingTasks_whenOperationsAreRunning_shouldWaitForAllOfThem() async {
        // Given
        let pendingTasks = Internals.PendingTasks()
        let count = Box(0)

        // When
        for _ in 0..<5 {
            pendingTasks.run {
                count.withLock { $0 += 1 }
            }
        }

        await pendingTasks.waitUntilIdle()

        // Then
        #expect(count.withLock { $0 } == 5)
    }

    @Test
    func pendingTasks_whenIdle_shouldReturnImmediately() async {
        // Given
        let pendingTasks = Internals.PendingTasks()

        // Then
        await pendingTasks.waitUntilIdle()
    }

    @Test
    func pendingTasks_whenStartedAgainDuringADrain_shouldWaitForTheNewEpochToo() async {
        // Given
        let pendingTasks = Internals.PendingTasks()
        let secondRan = Box(false)

        // When
        pendingTasks.run {
            pendingTasks.run {
                secondRan.withLock { $0 = true }
            }
        }

        await pendingTasks.waitUntilIdle()

        // Then
        #expect(secondRan.withLock { $0 })
    }

    @Test
    func pendingTasks_whenCallingTaskIsCancelled_shouldReturnWithoutJoiningCurrentEpoch() async throws {
        // Given
        let pendingTasks = Internals.PendingTasks()
        let started = AsyncSignal()
        let release = AsyncSignal()
        let finished = Box(false)

        // Work that stays in flight until the test explicitly lets it finish, so
        // `waitUntilIdle` has a real epoch to join (and, before the fix, to spin against)
        // instead of returning immediately because nothing was running.
        pendingTasks.run {
            started.signal()
            try? await release.wait()
        }

        try await started.wait()

        let waiter = _Concurrency.Task {
            await pendingTasks.waitUntilIdle()
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

        // Cleanup: let the blocked operation finish and drain the tracker for real, and give
        // the stray `waiter` (still spinning above if the assertion just failed) a chance to
        // settle.
        release.signal()
        await pendingTasks.waitUntilIdle()
    }
}
