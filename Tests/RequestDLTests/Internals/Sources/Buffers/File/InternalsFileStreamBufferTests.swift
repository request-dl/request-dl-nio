//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct InternalsFileStreamBufferTests {

    @Test
    func writeData_whenCallingTaskIsCancelledBeforeItRuns_shouldThrowCancellationError() async throws {
        try await withTemporaryFileURL("stream.bin") { url in
            let stream = try await Internals.FileStreamBuffer(writingTo: .init(url))

            let task = _Concurrency.Task<Void, Error> {
                try await stream.writeData(Data("Hello world".utf8))
            }
            task.cancel()

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

            let task = _Concurrency.Task<Data?, Error> {
                try await stream.readData(length: UInt64(data.count))
            }
            task.cancel()

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
