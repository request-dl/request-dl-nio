//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
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

    /// One `Content-Encoding` field line per element, which is how a real response carries
    /// stacked encodings when the server doesn't comma-join them itself.
    private func responseHead(contentEncodings: String...) -> Internals.ResponseHead {
        .init(
            url: "https://example.com",
            status: .init(code: 200, reason: "OK"),
            version: .init(minor: 1, major: 1),
            headers: contentEncodings.map { .init(name: "Content-Encoding", value: $0) },
            isKeepAlive: true
        )
    }

    private func responseHead(contentEncoding: String) -> Internals.ResponseHead {
        responseHead(contentEncodings: contentEncoding)
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

    // MARK: - Stacked Content-Encoding

    /// RFC 9110 §5.2 makes several field lines of one name equivalent to a single comma-joined
    /// line, so `gzip` then `br` means the body was compressed twice.
    ///
    /// Taking only `.first` decoded gzip and handed the caller bytes that were still
    /// brotli-compressed while reporting success — and `Internals.CacheControl` stored those
    /// wrong bytes on the way past.
    @Test
    func resolvedStream_whenContentEncodingIsStackedAcrossFieldLines_throws() async throws {
        // Given
        let source = Internals.AsyncStream<Internals.DataBuffer>()
        source.close()

        let dispatch = Internals.ManualDecompressionDispatch.dispatch(algorithms: [MockIdentityAlgorithm()])

        // When / Then
        #expect(throws: Internals.UnsupportedContentEncodingError.self) {
            _ = try dispatch.resolvedStream(
                for: responseHead(contentEncodings: "gzip", "br"),
                source: source
            )
        }
    }

    /// The same stacking, comma-joined into one field line, which the spec says means the same
    /// thing and which `.first` also mishandled — it matched the whole `"gzip, br"` string
    /// against each algorithm's `contentEncodingValue` and matched nothing.
    @Test
    func resolvedStream_whenContentEncodingIsStackedInOneFieldLine_throws() async throws {
        // Given
        let source = Internals.AsyncStream<Internals.DataBuffer>()
        source.close()

        let dispatch = Internals.ManualDecompressionDispatch.dispatch(algorithms: [MockIdentityAlgorithm()])

        // When / Then
        #expect(throws: Internals.UnsupportedContentEncodingError.self) {
            _ = try dispatch.resolvedStream(
                for: responseHead(contentEncoding: "gzip, br"),
                source: source
            )
        }
    }

    /// `identity` means "no transformation", so it doesn't make an encoding stacked. A server
    /// sending `identity, gzip` still only compressed the body once.
    @Test
    func resolvedStream_whenIdentityIsStackedAlongsideARealEncoding_decodesTheRealOne() async throws {
        // Given
        let source = Internals.AsyncStream<Internals.DataBuffer>()
        source.append(.success(await Internals.DataBuffer(Array("hello world".utf8))))
        source.close()

        let dispatch = Internals.ManualDecompressionDispatch.dispatch(algorithms: [MockIdentityAlgorithm()])

        // When
        let output = try dispatch.resolvedStream(
            for: responseHead(contentEncodings: "identity", "gzip"),
            source: source
        )

        var iterator = output.makeAsyncIterator()
        var collected = Data()
        while var chunk = try await iterator.next() {
            collected += await chunk.readData(chunk.readableBytes) ?? Data()
        }

        // Then
        #expect(collected == Data("hello world".utf8))
    }

    // MARK: - Abandoned/unread streams

    /// Thread-safe count of how many times a `CountingDecompressorStream` was actually asked to
    /// decompress a chunk.
    final class CallCounter: @unchecked Sendable {
        private let lock = Lock()
        private var _count = 0

        var count: Int { lock.withLock { _count } }

        func increment() {
            lock.withLock { _count += 1 }
        }
    }

    struct CountingDecompressorStream: Internals.DecompressorStream {
        let counter: CallCounter

        mutating func callAsFunction(decompressing bytes: Data) throws -> Data {
            counter.increment()
            return bytes
        }

        mutating func finish() throws -> Data {
            Data()
        }
    }

    struct CountingAlgorithm: Internals.DecompressionAlgorithm {
        let counter: CallCounter
        var contentEncodingValue: String { "gzip" }

        func callAsFunction() throws -> any Internals.DecompressorStream {
            CountingDecompressorStream(counter: counter)
        }
    }

    /// Regression coverage: `decompressing(_:using:)`'s background task used to have nothing
    /// stopping it once its returned stream was discarded unread -- it kept pulling `source`,
    /// decompressing every chunk, and (under `.untilFirstIteration`, which buffers until read)
    /// growing without bound, for a body nobody asked for. `Internals.AsyncStream
    /// .withTerminationToken(_:)` exists specifically to close this: dropping the returned stream
    /// without ever reading it must cancel that task instead.
    @Test
    func resolvedStream_whenNeverRead_cancelsTheDecompressionTaskInsteadOfRunningForever() async throws {
        // Given
        let counter = CallCounter()
        let source = Internals.AsyncStream<Internals.DataBuffer>()
        let dispatch = Internals.ManualDecompressionDispatch.dispatch(algorithms: [CountingAlgorithm(counter: counter)])

        source.append(.success(await Internals.DataBuffer(Array("first".utf8))))

        // When: the resolved stream is created and immediately discarded -- assigned to nothing,
        // never iterated -- exactly the "inspected only the response head" scenario this guards
        // against.
        _ = try dispatch.resolvedStream(for: responseHead(contentEncoding: "gzip"), source: source)

        // Gives the background task a chance to run, process whatever was already buffered, and
        // observe its own cancellation on the next suspension.
        try await Task.sleep(nanoseconds: 100_000_000)

        let countOnceAbandoned = counter.count

        // More data keeps arriving on `source` well after the stream that would have consumed it
        // was discarded.
        source.append(.success(await Internals.DataBuffer(Array("second".utf8))))
        source.append(.success(await Internals.DataBuffer(Array("third".utf8))))
        source.close()

        try await Task.sleep(nanoseconds: 100_000_000)

        // Then: nothing decompressed the later chunks -- the task was already cancelled and gone,
        // not still running and simply slow.
        #expect(counter.count == countOnceAbandoned)
    }

    /// Surrounding whitespace is part of the comma-joined grammar, not part of the token.
    @Test
    func resolvedStream_whenContentEncodingHasSurroundingWhitespace_stillMatches() async throws {
        // Given
        let source = Internals.AsyncStream<Internals.DataBuffer>()
        source.append(.success(await Internals.DataBuffer(Array("hello world".utf8))))
        source.close()

        let dispatch = Internals.ManualDecompressionDispatch.dispatch(algorithms: [MockIdentityAlgorithm()])

        // When
        let output = try dispatch.resolvedStream(
            for: responseHead(contentEncoding: "  GZIP  "),
            source: source
        )

        var iterator = output.makeAsyncIterator()
        var collected = Data()
        while var chunk = try await iterator.next() {
            collected += await chunk.readData(chunk.readableBytes) ?? Data()
        }

        // Then
        #expect(collected == Data("hello world".utf8))
    }
}
