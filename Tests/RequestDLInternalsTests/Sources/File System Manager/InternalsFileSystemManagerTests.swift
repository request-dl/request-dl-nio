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
}
