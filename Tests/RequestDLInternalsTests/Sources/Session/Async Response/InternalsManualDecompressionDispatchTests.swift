//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

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

    private func responseHeadWithNoContentEncoding() -> Internals.ResponseHead {
        .init(
            url: "https://example.com",
            status: .init(code: 200, reason: "OK"),
            version: .init(minor: 1, major: 1),
            headers: [],
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

    /// The decompression fallback path must not retain its entire decoded body in memory
    /// forever. The stream `decompressing(_:using:)` builds must not use the default
    /// `.unbounded` buffering policy, the same `ReplaySubject`-backed policy
    /// `Internals.DownloadBuffer.stream` deliberately avoids (`.untilFirstIteration` instead) for
    /// exactly this reason: `.unbounded` never releases what it has already handed a reader,
    /// which for a large streamed download (the `.brotli` fallback under `.nio`, or any custom
    /// `Decompressor`) would keep every decoded chunk resident for the life of the stream.
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
    /// Taking only `.first` would decode gzip and hand the caller bytes that are still
    /// brotli-compressed while reporting success, and `Internals.CacheControl` would store those
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
    /// thing. Matching the whole `"gzip, br"` string against each algorithm's
    /// `contentEncodingValue` would match nothing.
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

    /// `decompressing(_:using:)`'s background task must stop once its returned stream is
    /// discarded unread. Otherwise it keeps pulling `source`, decompressing every chunk, and
    /// (under `.untilFirstIteration`, which buffers until read) growing without bound, for a body
    /// nobody asked for. `Internals.AsyncStream.withTerminationToken(_:)` exists specifically to
    /// prevent this: dropping the returned stream without ever reading it must cancel that task.
    @Test
    func resolvedStream_whenNeverRead_cancelsTheDecompressionTaskInsteadOfRunningForever() async throws {
        // Given
        let counter = CallCounter()
        let source = Internals.AsyncStream<Internals.DataBuffer>()
        let dispatch = Internals.ManualDecompressionDispatch.dispatch(algorithms: [CountingAlgorithm(counter: counter)])

        source.append(.success(await Internals.DataBuffer(Array("first".utf8))))

        // When: the resolved stream is created and immediately discarded (assigned to nothing,
        // never iterated), exactly the "inspected only the response head" scenario this guards
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

        // Then: nothing decompressed the later chunks: the task was already cancelled and gone,
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

    // MARK: - Flow control

    /// Deterministic, position-dependent bytes, so a reassembled body that dropped, repeated or
    /// reordered anything cannot compare equal by accident.
    private func pattern(_ range: Range<Int>) -> Data {
        Data(range.map { UInt8(truncatingIfNeeded: $0 % 251) })
    }

    /// A metered source whose decoded stream nobody is reading yet, with 16 KiB already waiting
    /// in it: sixteen times what either window lets through before pausing.
    private func meteredSource() async -> (Internals.AsyncStream<Internals.DataBuffer>, Internals.FlowControlWindow) {
        let window = Internals.FlowControlWindow(highWatermark: 1_024, lowWatermark: 512)
        let source = Internals.AsyncStream<Internals.DataBuffer>(flowControl: window)

        for offset in stride(from: 0, to: 16_384, by: 1_024) {
            source.append(.success(await Internals.DataBuffer(pattern(offset..<offset + 1_024))))
        }

        source.close()
        return (source, window)
    }

    /// The decoding task is its source's reader, so it is what credits the source's window. Left
    /// unmetered, it drained a source that was holding the network back into an output nobody was
    /// holding back, which moved the unbounded backlog one stage downstream instead of removing
    /// it: the source's window never filled, and the network was never paused.
    ///
    /// With its output metered too, it stops pulling as soon as its own output is full, so the
    /// rest stays in the source, counted, where it keeps the producer upstream paused.
    @Test
    func resolvedStream_whenSourceIsMetered_stopsPullingOnceItsOwnOutputIsFull() async throws {
        // Given
        let (source, sourceWindow) = await meteredSource()
        let dispatch = Internals.ManualDecompressionDispatch.dispatch(algorithms: [MockIdentityAlgorithm()])

        // When
        let output = try dispatch.resolvedStream(for: responseHead(contentEncoding: "gzip"), source: source)
        let outputWindow = try #require(output.flowControlWindow)

        // Then: the decoder pulls two chunks (the second takes its output past the high
        // watermark) and parks, leaving the other fourteen counted against the source.
        try await eventually { outputWindow.waitingCountForTesting == 1 }

        #expect(outputWindow.bufferedBytesForTesting == 2_048)
        #expect(sourceWindow.bufferedBytesForTesting == 14_336)
        #expect(!sourceWindow.isWritable)

        // Reading the output is what lets it go on, all the way through, intact.
        var collected = Data()
        for try await chunk in Internals.AsyncBytes(logger: nil, totalSize: .zero, stream: output) {
            collected += chunk
        }

        #expect(collected == pattern(0..<16_384))
        #expect(outputWindow.peakBufferedBytesForTesting <= 2_048)
        #expect(sourceWindow.bufferedBytesForTesting == 0)
    }

    /// Discarding the decoded stream unread cancels the decoding task (see
    /// `resolvedStream_whenNeverRead_cancelsTheDecompressionTaskInsteadOfRunningForever`). While
    /// parked on its own full output, that task has to be woken for the cancellation to mean
    /// anything, and once it is gone the source's window has to be released with it: nothing
    /// will ever credit it again, and upstream, on the NIO path, a whole connection would stay
    /// paused waiting for that.
    @Test
    func resolvedStream_whenDiscardedWhileParked_releasesTheSourceWindow() async throws {
        // Given
        let (source, sourceWindow) = await meteredSource()
        let dispatch = Internals.ManualDecompressionDispatch.dispatch(algorithms: [MockIdentityAlgorithm()])

        let outputWindow: Internals.FlowControlWindow

        do {
            let output = try dispatch.resolvedStream(for: responseHead(contentEncoding: "gzip"), source: source)
            outputWindow = try #require(output.flowControlWindow)

            try await eventually { outputWindow.waitingCountForTesting == 1 }
            #expect(!sourceWindow.isReleasedForTesting)
        }

        // Then
        try await eventually { sourceWindow.isReleasedForTesting }
        #expect(outputWindow.waitingCountForTesting == 0)
    }

    /// An unmetered source keeps the previous, unmetered behaviour end to end: nothing upstream
    /// could honour a window anyway (the cached-response replay, the `URLSession` delegate).
    @Test
    func resolvedStream_whenSourceIsNotMetered_leavesTheOutputUnmetered() async throws {
        // Given
        let source = Internals.AsyncStream<Internals.DataBuffer>()
        source.close()

        let dispatch = Internals.ManualDecompressionDispatch.dispatch(algorithms: [MockIdentityAlgorithm()])

        // When
        let output = try dispatch.resolvedStream(for: responseHead(contentEncoding: "gzip"), source: source)

        // Then
        #expect(output.flowControlWindow == nil)
    }

    // MARK: - requiresManualDecoding(for:)

    /// `.skip` never requires this package's own decoding: either decompression is disabled, or
    /// every configured algorithm was already decoded natively before these bytes were observed.
    /// Either way there is nothing left for `requiresManualDecoding(for:)` to say yes to.
    @Test
    func requiresManualDecoding_whenSkipping_isAlwaysFalse() {
        #expect(
            !Internals.ManualDecompressionDispatch.skip.requiresManualDecoding(
                for: responseHead(contentEncoding: "gzip")
            )
        )
        #expect(
            !Internals.ManualDecompressionDispatch.skip.requiresManualDecoding(for: responseHeadWithNoContentEncoding())
        )
    }

    /// This is the exact check `Internals.ClientResponseReceiver` (`.nio`) and
    /// `Internals.URLSessionClient`'s `runExchange` (`.urlSession`) both gate their cache tee on,
    /// so a caching response this package still has to decode itself is never persisted still
    /// compressed. See
    /// `InternalsClientSessionTaskTests`/`InternalsURLSessionClientSessionTaskTests` for the
    /// executor-level tests this one complements.
    @Test
    func requiresManualDecoding_whenDispatchingARealEncoding_isTrue() {
        let dispatch = Internals.ManualDecompressionDispatch.dispatch(algorithms: [MockIdentityAlgorithm()])
        #expect(dispatch.requiresManualDecoding(for: responseHead(contentEncoding: "gzip")))
    }

    @Test
    func requiresManualDecoding_whenNoContentEncodingHeader_isFalse() {
        let dispatch = Internals.ManualDecompressionDispatch.dispatch(algorithms: [MockIdentityAlgorithm()])
        #expect(!dispatch.requiresManualDecoding(for: responseHeadWithNoContentEncoding()))
    }

    /// `identity` stands for "no transformation": nothing to decode, so nothing to cache-gate
    /// against either.
    @Test
    func requiresManualDecoding_whenContentEncodingIsIdentity_isFalse() {
        let dispatch = Internals.ManualDecompressionDispatch.dispatch(algorithms: [MockIdentityAlgorithm()])
        #expect(!dispatch.requiresManualDecoding(for: responseHead(contentEncoding: "identity")))
    }

    /// A transport that already decoded this specific encoding natively (`nativelyDecoded`) has
    /// already handed over plain bytes by the time the cache tee would see them, even though this
    /// dispatch is `.dispatch` for the request as a whole (a mixed list under `.nio`, say).
    @Test
    func requiresManualDecoding_whenEncodingIsAlreadyNativelyDecoded_isFalse() {
        let dispatch = Internals.ManualDecompressionDispatch.dispatch(
            algorithms: [MockIdentityAlgorithm()],
            nativelyDecoded: ["gzip"]
        )
        #expect(!dispatch.requiresManualDecoding(for: responseHead(contentEncoding: "gzip")))
    }
}
