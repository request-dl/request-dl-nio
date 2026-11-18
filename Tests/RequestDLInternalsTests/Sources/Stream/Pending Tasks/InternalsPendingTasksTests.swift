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

        // Observed from an unstructured task instead of awaited directly: a loop that only
        // used `try?` would leave `waiter` spinning until `release` is signalled below,
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

    // MARK: - Priority

    @Test
    func pendingTasks_whenStartedFromAHighPriorityTask_shouldRunTheWorkAtItsPriority() async {
        // Given
        let pendingTasks = Internals.PendingTasks()
        let observed = Box<_Concurrency.TaskPriority?>(nil)

        // When
        await _Concurrency.Task(priority: .high) {
            pendingTasks.run {
                observed.withLock { $0 = _Concurrency.Task.currentPriority }
            }
        }.value

        await pendingTasks.waitUntilIdle()

        // Then: inherited, not a fixed low priority the caller ends up waiting on.
        #expect(observed.withLock { $0 } == .high)
    }

    @Test
    func pendingTasks_whenTheOperationGivesAPriority_shouldRunTheWorkAtIt() async {
        // Given: a tracker with a priority of its own, started from a high priority task.
        let pendingTasks = Internals.PendingTasks(priority: .utility)
        let observed = Box<[_Concurrency.TaskPriority]>([])

        // When
        await _Concurrency.Task(priority: .high) {
            pendingTasks.run {
                observed.withLock { $0.append(_Concurrency.Task.currentPriority) }
            }

            pendingTasks.run(priority: .medium) {
                observed.withLock { $0.append(_Concurrency.Task.currentPriority) }
            }
        }.value

        await pendingTasks.waitUntilIdle()

        // Then: the tracker's priority, unless the operation brings its own.
        #expect(observed.withLock { $0.sorted(by: { $0.rawValue < $1.rawValue }) } == [.utility, .medium])
    }

    /// An event loop callback is not a task: what the work needs to run at is the priority of the
    /// request it belongs to, taken while still in that request's task.
    @Test
    func pendingTasks_whenStartedFromOutsideTheRequestWithItsPriority_shouldRunTheWorkAtIt() async {
        // Given
        let pendingTasks = Internals.PendingTasks()
        let observed = Box<_Concurrency.TaskPriority?>(nil)

        let captured = await _Concurrency.Task(priority: .high) {
            _Concurrency.Task.currentPriority
        }.value

        // When
        await _Concurrency.Task.detached(priority: .background) {
            pendingTasks.run(priority: captured) {
                observed.withLock { $0 = _Concurrency.Task.currentPriority }
            }
        }.value

        await pendingTasks.waitUntilIdle()

        // Then
        #expect(observed.withLock { $0 } == .high)
    }
}
