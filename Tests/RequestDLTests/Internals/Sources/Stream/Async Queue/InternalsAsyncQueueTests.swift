//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL

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
}
