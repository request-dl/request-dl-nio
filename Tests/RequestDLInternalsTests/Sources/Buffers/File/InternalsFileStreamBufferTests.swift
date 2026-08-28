//
// See LICENSE for this package's licensing information.
//

@_spi(Testing) import SwiftAsyncStream
import SwiftAsyncTesting
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

@Suite(.concurrent(2), .nonFatalWatchdog)
struct InternalsFileStreamBufferTests {

    @Test
    func writeData_whenCallingTaskIsCancelledBeforeItRuns_shouldThrowCancellationError() async throws {
        try await withTemporaryFileURL("stream.bin") { url in
            let stream = try await Internals.FileStreamBuffer(writingTo: .init(url))

            // Holding the lock first, then waiting for the task to actually queue behind it,
            // makes "cancelled before it runs" deterministic instead of a race between
            // `task.cancel()` and the task getting scheduled — under CI scheduler contention,
            // a freshly created task can start and finish before the creating task even reaches
            // `cancel()`. `AsyncLock` guarantees a cancelled waiter still takes its turn and
            // runs `writeData`'s loop, which checks `Task.checkCancellation()` before doing
            // anything else — see `Internals.FileStreamBuffer.writeData`.
            await stream.lock.lock()

            let task = _Concurrency.Task<Void, Error> {
                try await stream.writeData(Data("Hello world".utf8))
            }
            try await stream.lock.waitForPendingOperations(1, timeout: 5)

            task.cancel()
            stream.lock.unlock()

            await #expect(throws: CancellationError.self) {
                try await task.value
            }

            try await stream.close()
        }
    }

    @Test
    func readData_whenCallingTaskIsCancelledBeforeItRuns_shouldThrowCancellationError() async throws {
        try await withTemporaryFileURL("stream.bin") { url in
            let data = Data("Hello world".utf8)
            try data.write(to: url)

            let stream = try await Internals.FileStreamBuffer(readingFrom: .init(url))

            // Same reasoning as the writeData test above.
            await stream.lock.lock()

            let task = _Concurrency.Task<Data?, Error> {
                try await stream.readData(length: UInt64(data.count))
            }
            try await stream.lock.waitForPendingOperations(1, timeout: 5)

            task.cancel()
            stream.lock.unlock()

            await #expect(throws: CancellationError.self) {
                try await task.value
            }

            try await stream.close()
        }
    }

    /// Regression test for the read/write path running blocking syscalls directly on the
    /// Swift Concurrency cooperative thread pool: under `swift-testing`'s parallel execution,
    /// enough concurrent instances doing that used to saturate the pool and could make a single
    /// instance's critical section look "stuck" to `AsyncLock.Watchdog`, five seconds later,
    /// even though no lock was ever contended between them. Each instance below has its own
    /// file and its own lock, so this exercises exactly that many-instances-at-once shape.
    @Test
    func manyInstances_whenRunningConcurrently_shouldAllCompleteWithoutStallingTheCooperativePool() async throws {
        let expected = Data(repeating: 0x2A, count: 4_096)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<64 {
                group.addTask {
                    try await withTemporaryFileURL("stream.bin") { url in
                        let writer = try await Internals.FileStreamBuffer(writingTo: .init(url))
                        try await writer.writeData(expected)
                        try await writer.close()

                        let reader = try await Internals.FileStreamBuffer(readingFrom: .init(url))
                        let read = try await reader.readData(length: UInt64(expected.count))
                        try await reader.close()

                        #expect(read == expected)
                    }
                }
            }

            try await group.waitForAll()
        }
    }
}
