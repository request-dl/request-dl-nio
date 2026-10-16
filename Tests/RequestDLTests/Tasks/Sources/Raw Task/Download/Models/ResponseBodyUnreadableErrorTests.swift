//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// A chunk that was received and can't be read back ends the body with an error, and the error is
/// ``ResponseBodyUnreadableError``: ending it quietly would look exactly like a response that
/// finished, with the rest of it missing.
struct ResponseBodyUnreadableErrorTests {

    @Test
    func aChunkThatCannotBeReadBack_failsTheReaderWithResponseBodyUnreadableError() async throws {
        // Given: what `Internals.AsyncBytes` throws for it (see `InternalsDownloadBufferTests`).
        let stream = Internals.AsyncStream<Internals.DataBuffer>()
        await stream.append(.success(Internals.DataBuffer(Data("first".utf8))))
        await stream.append(.failure(AsyncBytesReadError()))

        let bytes = AsyncBytes(
            seed: .withoutCancellation,
            bytes: Internals.AsyncBytes(logger: nil, totalSize: 5, stream: stream)
        )

        var iterator = bytes.makeAsyncIterator()

        // When
        let first = try await iterator.next()

        // Then: what was readable is delivered, and then the read fails instead of ending.
        #expect(first == Data("first".utf8))

        await #expect(throws: ResponseBodyUnreadableError.self) {
            _ = try await iterator.next()
        }
    }

    @Test
    func theErrorDescribesItself() {
        #expect(!String(describing: ResponseBodyUnreadableError()).isEmpty)
    }
}
