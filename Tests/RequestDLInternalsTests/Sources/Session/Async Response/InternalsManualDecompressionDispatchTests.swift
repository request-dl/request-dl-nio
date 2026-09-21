//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct InternalsManualDecompressionDispatchTests {

    struct MockIdentityDecompressorStream: Internals.DecompressorStream {
        mutating func callAsFunction(decompressing bytes: Data) throws -> Data {
            bytes
        }

        mutating func finish() throws -> Data {
            Data()
        }
    }

    struct MockIdentityAlgorithm: Internals.DecompressionAlgorithm {
        var contentEncodingValue: String { "gzip" }

        func callAsFunction() throws -> any Internals.DecompressorStream {
            MockIdentityDecompressorStream()
        }
    }

    private func responseHead(contentEncoding: String) -> Internals.ResponseHead {
        .init(
            url: "https://example.com",
            status: .init(code: 200, reason: "OK"),
            version: .init(minor: 1, major: 1),
            headers: [.init(name: "Content-Encoding", value: contentEncoding)],
            isKeepAlive: true
        )
    }

    @Test
    func resolvedStream_whenDispatching_decodesEveryChunk() async throws {
        // Given
        let source = Internals.AsyncStream<Internals.DataBuffer>()
        source.append(.success(await Internals.DataBuffer(Array("hello ".utf8))))
        source.append(.success(await Internals.DataBuffer(Array("world".utf8))))
        source.close()

        let dispatch = Internals.ManualDecompressionDispatch.dispatch(algorithms: [MockIdentityAlgorithm()])

        // When
        let output = try dispatch.resolvedStream(for: responseHead(contentEncoding: "gzip"), source: source)

        var iterator = output.makeAsyncIterator()
        var collected = Data()
        while var chunk = try await iterator.next() {
            collected += await chunk.readData(chunk.readableBytes) ?? Data()
        }

        // Then
        #expect(collected == Data("hello world".utf8))
    }

    /// Regression test for the decompression fallback path retaining its entire decoded body in
    /// memory forever. The stream `decompressing(_:using:)` builds used to be constructed with
    /// the default `.unbounded` buffering policy, the same `ReplaySubject`-backed policy
    /// `Internals.DownloadBuffer.stream` deliberately avoids (`.untilFirstIteration` instead) for
    /// exactly this reason: `.unbounded` never releases what it has already handed a reader,
    /// which for a large streamed download (the `.brotli` fallback under `.nio`, or any custom
    /// `Decompressor`) meant every decoded chunk stayed resident for the life of the stream.
    ///
    /// `.untilFirstIteration` makes the stream single use: once a first reader has drained it,
    /// a second iterator has nothing left to replay and reports `AlreadyConsumedError` instead of
    /// happily handing back a second full copy. A stream still built with `.unbounded` would fail
    /// this assertion by replaying successfully.
    @Test
    func resolvedStream_whenDispatching_releasesBufferToFirstReaderOnly() async throws {
        // Given
        let source = Internals.AsyncStream<Internals.DataBuffer>()
        source.append(.success(await Internals.DataBuffer(Array("hello".utf8))))
        source.close()

        let dispatch = Internals.ManualDecompressionDispatch.dispatch(algorithms: [MockIdentityAlgorithm()])
        let output = try dispatch.resolvedStream(for: responseHead(contentEncoding: "gzip"), source: source)

        var first = output.makeAsyncIterator()
        while try await first.next() != nil {}

        // When
        var second = output.makeAsyncIterator()

        // Then
        await #expect(throws: AlreadyConsumedError.self) {
            _ = try await second.next()
        }
    }
}
