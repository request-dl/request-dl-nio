//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsFileSystemManagerTests {

    /// The portable (`--disable-default-traits`, no `NIOCore`) thread pool's work queue must
    /// dequeue in O(1): `Array.removeFirst()` would shift every remaining item on every dequeue
    /// while holding the pool's lock, which is O(*n*) per item and O(*n*²) to drain a burst, with
    /// every competing worker thread paying for the shift. `PortableBlockingPool` is backed by
    /// `FIFOQueue`, an O(1)-amortized dequeue.
    ///
    /// This doesn't assert on timing (flaky under CI load), but a few thousand queued operations
    /// still exercise the dequeue path, while asserting the contract: every operation runs
    /// exactly once and returns its own result, under real concurrent pressure from many callers
    /// at once. Runs the same way under the `NIOCore` trait too (against `NIOThreadPool`), so it
    /// covers both traits rather than only the portable path.
    @Test
    func run_whenManyConcurrentOperationsQueueAtOnce_completesEachExactlyOnce() async throws {
        // Given
        let operationCount = 4_000

        // When
        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<operationCount {
                group.addTask {
                    try await Internals.FileSystemManager.run { index }
                }
            }

            var collected: [Int] = []
            for try await value in group {
                collected.append(value)
            }
            return collected
        }

        // Then
        #expect(results.sorted() == Array(0..<operationCount))
    }

    #if !canImport(NIOCore)

    /// The pool starts no thread until there is work for one.
    @Test
    func portablePool_whenCreated_hasStartedNoThreads() {
        // Given / When
        let pool = PortableBlockingPool(threadCount: 32)

        // Then
        #expect(pool.startedThreadCount == 0)
    }

    @Test
    func portablePool_whenWorkRunsOneAtATime_startsFarFewerThreadsThanItsLimit() async throws {
        // Given
        let pool = PortableBlockingPool(threadCount: 32)

        // When
        for index in 0..<50 {
            let result = try await pool.run { index }
            #expect(result == index)
        }

        // Then: a worker that has only just finished may not be waiting again yet, so a second
        // thread can start; nothing close to the limit does.
        #expect(pool.startedThreadCount >= 1)
        #expect(pool.startedThreadCount <= 4)
    }

    /// The limit is still reachable: a burst whose operations all wait for each other can only
    /// finish if that many run at once.
    @Test
    func portablePool_whenOperationsNeedToRunAtOnce_startsThatManyThreads() async throws {
        // Given
        let limit = 8
        let pool = PortableBlockingPool(threadCount: limit)
        let barrier = Barrier(parties: limit)

        // When
        let results = try await withThrowingTaskGroup(of: Bool.self) { group in
            for _ in 0..<limit {
                group.addTask {
                    try await pool.run { barrier.arriveAndWait() }
                }
            }

            var collected: [Bool] = []
            for try await value in group {
                collected.append(value)
            }
            return collected
        }

        // Then
        #expect(results == Array(repeating: true, count: limit))
        #expect(pool.startedThreadCount == limit)
    }

    /// More work than threads still all runs, once each, on no more than the limit.
    @Test
    func portablePool_whenMoreWorkThanThreads_runsAllOfItWithoutExceedingTheLimit() async throws {
        // Given
        let limit = 4
        let pool = PortableBlockingPool(threadCount: limit)

        // When
        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for index in 0..<500 {
                group.addTask {
                    try await pool.run { index }
                }
            }

            var collected: [Int] = []
            for try await value in group {
                collected.append(value)
            }
            return collected
        }

        // Then
        #expect(results.sorted() == Array(0..<500))
        #expect(pool.startedThreadCount <= limit)
    }

    #endif
}

#if !canImport(NIOCore)

import Foundation

/// Lets `parties` blocking operations wait for each other, so they can only all finish by running
/// at the same time. Gives up after ten seconds and answers `false`.
private final class Barrier: @unchecked Sendable {

    private let condition = NSCondition()
    private let parties: Int
    private var arrived = 0

    init(parties: Int) {
        self.parties = parties
    }

    func arriveAndWait() -> Bool {
        condition.lock()
        defer { condition.unlock() }

        arrived += 1
        condition.broadcast()

        let deadline = Date().addingTimeInterval(10)

        while arrived < parties {
            guard condition.wait(until: deadline) else {
                return false
            }
        }

        return true
    }
}

#endif
