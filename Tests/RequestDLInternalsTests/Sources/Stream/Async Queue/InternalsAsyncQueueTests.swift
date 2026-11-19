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

        // Cleanup: let the blocked operation finish and drain the queue for real, and give the
        // stray `waiter` (still spinning above if the assertion just failed) a chance to settle.
        release.signal()
        await queue.waitUntilIdle()
    }

    // MARK: - Priority

    /// What the operations run at is the priority of whoever made the queue, however they were
    /// enqueued: a producer that is not a task at all (an event loop) has none worth inheriting.
    @Test
    func asyncQueue_whenCreatedByAHighPriorityTask_shouldRunOperationsAtItsPriority() async {
        // Given: a queue made by a high priority task, the consumer of what it produces.
        let observed = Box<[_Concurrency.TaskPriority]>([])

        let queue = await _Concurrency.Task(priority: .high) {
            Internals.AsyncQueue()
        }.value

        // When: operations are enqueued from a low priority one.
        await _Concurrency.Task.detached(priority: .background) {
            for _ in 0..<3 {
                queue.addOperation {
                    observed.withLock { $0.append(_Concurrency.Task.currentPriority) }
                }
            }
        }.value

        await queue.waitUntilIdle()

        // Then: they ran at the creator's priority, not at a fixed low one.
        #expect(observed.withLock { $0 } == Array(repeating: .high, count: 3))
        #expect(queue.priorityForTesting == .high)
    }

    @Test
    func asyncQueue_whenGivenAPriority_shouldRunOperationsAtIt() async {
        // Given
        let observed = Box<_Concurrency.TaskPriority?>(nil)

        let queue = await _Concurrency.Task(priority: .high) {
            Internals.AsyncQueue(priority: .utility)
        }.value

        // When
        queue.addOperation {
            observed.withLock { $0 = _Concurrency.Task.currentPriority }
        }

        await queue.waitUntilIdle()

        // Then
        #expect(observed.withLock { $0 } == .utility)
    }
}
