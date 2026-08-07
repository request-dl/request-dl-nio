//
// See LICENSE for this package's licensing information.
//

import SystemPackage
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
        }
    }
}
