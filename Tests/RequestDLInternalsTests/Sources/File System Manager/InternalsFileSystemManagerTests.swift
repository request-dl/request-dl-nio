//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

struct InternalsFileSystemManagerTests {

    /// Regression test for the portable (`--disable-default-traits`, no `NIOCore`) thread pool's
    /// work queue: `PortableBlockingPool` used to dequeue with `Array.removeFirst()`, shifting
    /// every remaining item on every dequeue while holding the pool's lock -- O(*n*) per item,
    /// O(*n*²) to drain a burst, with every competing worker thread paying for the shift. Now
    /// backed by `FIFOQueue`, an O(1)-amortized dequeue.
    ///
    /// This doesn't assert on timing (flaky under CI load), but a few thousand queued operations
    /// still exercise the same dequeue path a shift-based queue would have paid quadratic cost
    /// walking, while asserting the fix didn't change the contract: every operation still runs
    /// exactly once and returns its own result, under real concurrent pressure from many callers
    /// at once. Runs the same way under the `NIOCore` trait too (against `NIOThreadPool`, already
    /// correct), so this is a cross-trait regression guard rather than only exercising the
    /// portable path.
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
}
