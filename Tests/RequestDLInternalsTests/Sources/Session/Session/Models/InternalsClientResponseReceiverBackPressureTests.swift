//
// See LICENSE for this package's licensing information.
//

// Drives `Internals.Session.client()`/`.execute()` directly against a real socket, like
// `InternalsClientResponseReceiverTests`: the back pressure under test is AsyncHTTPClient's own
// `HTTPClientResponseDelegate` contract, which only the `.nio` executors have.
#if canImport(NIOCore)

import AsyncHTTPClient
import NIOCore
import NIOPosix
import SwiftAsyncStream
import SwiftAsyncTesting
import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// End-to-end coverage for `Internals.ClientResponseReceiver.didReceiveBodyPart(task:_:)`'s back
/// pressure: a reader slower than the network must hold the *connection* back, not have the
/// body pile up in memory, and no way of abandoning such a reader may leave the request hung.
///
/// Every test observes the server rather than trusting the client's own bookkeeping alone:
/// `StreamingServer` only writes while the socket accepts more, and counts what the kernel
/// actually took. Once the client stops reading from the socket, that count stalls a few
/// megabytes in, at whatever the kernel's socket buffers hold. With nothing pausing the
/// client, it instead races to the full body regardless of the reader, which is exactly what
/// each test's "the connection really paused" precondition rules out.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsClientResponseReceiverBackPressureTests {

    /// Far past the window plus any plausible socket buffering on either end, so "stalled well
    /// short of this" can only mean the client stopped reading from the socket.
    private static let largeBody = 32 * 1_048_576

    private static var window: (high: Int, low: Int) {
        (Internals.FlowControlWindow.defaultHighWatermark, Internals.FlowControlWindow.defaultLowWatermark)
    }

    /// How far past the high watermark the window can legitimately get: the part that crossed it,
    /// and, momentarily, that same part counted twice while `Internals.DownloadBuffer` charges what
    /// it emits before crediting what it dequeued. A generous multiple of NIO's largest read.
    private static let windowOvershoot = 512 * 1_024

    @Test
    func slowReader_pausesTheConnectionInsteadOfBufferingTheBody() async throws {
        try await withStreamingServer(totalBytes: Self.largeBody) { server in
            // Given
            let (task, step) = try await startDownload(server, provider: "slow-reader")
            let window = try #require(step.bytes.flowControlWindowForTesting)

            var iterator = step.bytes.makeAsyncIterator()
            var verifier = BodyVerifier()

            verifier.consume(try #require(try await iterator.next()))

            // When: the reader stops.
            let written = try await server.settledBytesWritten()

            // Then: the connection paused, and the backlog held in memory stayed within the window.
            #expect(written < Self.largeBody / 2)
            #expect(window.peakBufferedBytesForTesting <= Self.window.high + Self.windowOvershoot)
            #expect(window.waitingCountForTesting == 1)

            // And once the reader resumes, the whole body arrives, intact, still within the window.
            let (verified, _) = try await completing(within: 60) { [iterator, verifier] in
                var iterator = iterator
                var verifier = verifier

                while let chunk = try await iterator.next() {
                    verifier.consume(chunk)
                }

                return (verifier, iterator)
            }

            #expect(verified.isIntact)
            #expect(verified.position == Self.largeBody)
            #expect(window.peakBufferedBytesForTesting <= Self.window.high + Self.windowOvershoot)

            withExtendedLifetime(task) {}
        }
    }

    /// A `.length(n)` chunk bigger than the whole window can only complete with more input. The
    /// bytes waiting for it are credited back as they enter `Internals.DownloadBuffer`'s
    /// accumulator; counting them instead would pause the connection with nothing the reader
    /// could ever drain, and this would hang.
    @Test
    func chunkLargerThanTheWindow_stillCompletes() async throws {
        let totalBytes = 16 * 1_048_576
        let chunkLength = 3 * 1_048_576

        try await withStreamingServer(totalBytes: totalBytes) { server in
            // Given
            let (task, step) = try await startDownload(
                server,
                provider: "oversized-chunk",
                readingMode: .length(chunkLength)
            )

            // When
            let verified = try await completing(within: 60) {
                var verifier = BodyVerifier()

                for try await chunk in step.bytes {
                    #expect(chunk.count <= chunkLength)
                    verifier.consume(chunk)
                }

                return verifier
            }

            // Then
            #expect(verified.isIntact)
            #expect(verified.position == totalBytes)

            withExtendedLifetime(task) {}
        }
    }

    /// The decoding task behind manual decompression reads its source as fast as it can decode.
    /// Unmetered, it drained the receiver's window into an output nobody was holding back, so the
    /// connection was never paused however slow the actual reader was.
    @Test
    func slowReaderBehindManualDecompression_stillPausesTheConnection() async throws {
        try await withStreamingServer(
            totalBytes: Self.largeBody,
            headers: [("Content-Encoding", IdentityTestAlgorithm.contentEncoding)]
        ) { server in
            // Given
            let (task, step) = try await startDownload(
                server,
                provider: "slow-reader-decompressing",
                decompression: .enabled(algorithms: [IdentityTestAlgorithm()], limit: .none)
            )

            // The decoder's own window, not the receiver's.
            let window = try #require(step.bytes.flowControlWindowForTesting)

            var iterator = step.bytes.makeAsyncIterator()
            var verifier = BodyVerifier()

            verifier.consume(try #require(try await iterator.next()))

            // When
            let written = try await server.settledBytesWritten()

            // Then
            #expect(written < Self.largeBody / 2)
            #expect(window.peakBufferedBytesForTesting <= Self.window.high + Self.windowOvershoot)

            let (verified, _) = try await completing(within: 60) { [iterator, verifier] in
                var iterator = iterator
                var verifier = verifier

                while let chunk = try await iterator.next() {
                    verifier.consume(chunk)
                }

                return (verifier, iterator)
            }

            #expect(verified.isIntact)
            #expect(verified.position == Self.largeBody)

            withExtendedLifetime(task) {}
        }
    }

    // MARK: - Nothing hangs

    /// Nobody ever reads the body, and the response is dropped with the connection paused. The
    /// paused `didReceiveBodyPart` future must still complete, and the request must be
    /// cancelled, not left holding its connection for good.
    @Test
    func readerNeverStarts_droppingTheResponse_cancelsTheRequest() async throws {
        try await withStreamingServer(totalBytes: Self.largeBody) { server in
            // Given
            let window: Internals.FlowControlWindow

            do {
                let (task, step) = try await startDownload(server, provider: "never-read")
                window = try #require(step.bytes.flowControlWindowForTesting)

                let written = try await server.settledBytesWritten()
                #expect(written < Self.largeBody / 2)
                #expect(window.waitingCountForTesting == 1)

                // When: everything goes out of scope here.
                withExtendedLifetime((task, step)) {}
            }

            // Then
            try await eventually { window.isReleasedForTesting && window.waitingCountForTesting == 0 }
            try await eventually { server.isConnectionClosed }
            #expect(server.bytesWritten < Self.largeBody)
        }
    }

    /// The reader reads a little and then goes away for good (a `break`, or the task running
    /// the loop being cancelled) while the response itself is kept. Its iterator going away
    /// releases the window, so the request runs to completion instead of staying paused forever
    /// for a reader that can never come back.
    @Test
    func readerStopsAndItsTaskIsCancelled_letsTheRequestFinish() async throws {
        try await withStreamingServer(totalBytes: Self.largeBody) { server in
            // Given
            let (task, step) = try await startDownload(server, provider: "reader-cancelled")
            let window = try #require(step.bytes.flowControlWindowForTesting)
            let didReadFirstChunk = AsyncSignal()

            let reader = _Concurrency.Task {
                var iterator = step.bytes.makeAsyncIterator()
                _ = try await iterator.next()
                didReadFirstChunk.signal()

                // Parked, iterator in hand, until cancelled.
                try await _Concurrency.Task.sleep(nanoseconds: 3_600_000_000_000)
                _ = try await iterator.next()
            }

            try await didReadFirstChunk.wait()

            let written = try await server.settledBytesWritten()
            #expect(written < Self.largeBody / 2)
            #expect(window.waitingCountForTesting == 1)

            // When
            reader.cancel()
            _ = await reader.result

            // Then
            try await eventually { window.isReleasedForTesting }
            try await eventually(timeout: 60) { server.bytesWritten == Self.largeBody }

            withExtendedLifetime(task) {}
        }
    }

    /// The caller cancels the request while it is paused behind a reader that is still there.
    /// The window is released right away, by the cancellation itself, not only once the
    /// cancellation reaches `didReceiveError`, which AsyncHTTPClient defers until after a pending
    /// body part future completes whenever the response's end has already arrived. The
    /// reader then gets the failure instead of waiting for bytes that will never come.
    @Test
    func requestCancelledWhileParked_failsTheReaderInsteadOfHanging() async throws {
        try await withStreamingServer(totalBytes: Self.largeBody) { server in
            // Given
            let (task, step) = try await startDownload(server, provider: "cancelled-while-parked")
            let window = try #require(step.bytes.flowControlWindowForTesting)

            var iterator = step.bytes.makeAsyncIterator()
            _ = try await iterator.next()

            let written = try await server.settledBytesWritten()
            #expect(written < Self.largeBody / 2)
            #expect(window.waitingCountForTesting == 1)

            // When
            task.seed()

            // Then
            #expect(window.isReleasedForTesting)
            #expect(window.waitingCountForTesting == 0)

            let outcome = try await completing(within: 30) { [iterator] in
                var iterator = iterator
                var received = 0

                do {
                    while let chunk = try await iterator.next() {
                        received += chunk.count
                    }

                    return "finished after \(received) bytes"
                } catch {
                    return "failed"
                }
            }

            #expect(outcome == "failed")
            try await eventually { server.isConnectionClosed }
        }
    }

    /// The same cancellation, but with the body only a few KiB past the window, so the response's
    /// end has already arrived and sits in AsyncHTTPClient's own buffer behind the paused part.
    ///
    /// In that state AsyncHTTPClient does *not* report the cancellation to the delegate straight
    /// away: it discards its buffer and holds the error back until the pending body part future
    /// completes (`RequestBag.StateMachine.fail(_:)`, `.buffering(_, next: .eof)`). A window
    /// released only from `didReceiveError` would therefore stay shut, leaving a request that
    /// could never finish (`waitingCountForTesting` stuck at 1, `didReceiveError` never called)
    /// and a promise that could never be fulfilled, for as long as anything referenced it.
    ///
    /// Made deterministic with a window far smaller than a body that fits in a single write: the
    /// head, the whole body and its end then reach AsyncHTTPClient in one read, so by the time
    /// the first body part is paused the end is already queued right behind it.
    @Test
    func requestCancelledAfterTheEndAlreadyArrived_stillReleasesThePausedPart() async throws {
        let totalBytes = 16_384

        try await withStreamingServer(totalBytes: totalBytes) { server in
            // Given: nobody reads, so the first body part fills the window and waits.
            let (task, step) = try await startDownload(
                server,
                provider: "cancelled-after-end",
                readingMode: .length(1_024),
                flowControl: .init(highWatermark: 1_024, lowWatermark: 512)
            )
            let window = try #require(step.bytes.flowControlWindowForTesting)

            try await eventually { server.bytesWritten == totalBytes }
            try await eventually { window.waitingCountForTesting == 1 }

            // When
            task.seed()

            // Then: the paused part completes without the reader doing anything at all.
            try await eventually { window.isReleasedForTesting && window.waitingCountForTesting == 0 }

            // And the reader, when it does look, gets the cancellation, not a clean end of a
            // truncated body.
            let outcome = try await completing(within: 30) {
                do {
                    for try await _ in step.bytes {}
                    return "finished"
                } catch {
                    return "failed"
                }
            }

            #expect(outcome == "failed")
        }
    }

    /// The connection drops mid-body while the reader has stopped: the error has to reach the
    /// reader once it looks again, with the paused future completed along the way.
    @Test
    func connectionDropsWhileParked_failsTheReaderInsteadOfHanging() async throws {
        try await withStreamingServer(totalBytes: Self.largeBody) { server in
            // Given
            let (task, step) = try await startDownload(server, provider: "dropped-while-parked")
            let window = try #require(step.bytes.flowControlWindowForTesting)

            var iterator = step.bytes.makeAsyncIterator()
            _ = try await iterator.next()

            let written = try await server.settledBytesWritten()
            #expect(written < Self.largeBody / 2)
            #expect(window.waitingCountForTesting == 1)

            // When
            server.closeConnection()

            // Then
            let outcome = try await completing(within: 30) { [iterator] in
                var iterator = iterator

                do {
                    while try await iterator.next() != nil {}
                    return "finished"
                } catch {
                    return "failed"
                }
            }

            #expect(outcome == "failed")
            try await eventually { window.isReleasedForTesting && window.waitingCountForTesting == 0 }

            withExtendedLifetime(task) {}
        }
    }
}

// MARK: - Client

/// Starts a GET against `server` and returns once the response head is in, before any of the body
/// has been read.
private func startDownload(
    _ server: StreamingServer,
    provider: String,
    readingMode: Internals.DownloadStep.ReadingMode = .length(65_536),
    decompression: Internals.Decompression = .disabled,
    flowControl: Internals.FlowControlWindow = .init()
) async throws -> (SessionTask, Internals.DownloadStep) {
    let session = Internals.Session(
        provider: .identified("com.requestdl.tests.back-pressure.\(provider)", numberOfThreads: 1),
        configuration: .init()
    )

    let url = "http://127.0.0.1:\(server.port)"
    let client = try await session.client()

    let task = try await session.execute(
        client: client,
        request: try HTTPClient.Request(url: url),
        url: url,
        readingMode: readingMode,
        uploadingBytes: .zero,
        decompression: decompression,
        cache: nil,
        logger: nil,
        flowControl: flowControl
    )

    for try await step in task.response {
        if case .download(let download) = step {
            return (task, download)
        }
    }

    throw AnyError()
}

/// Checks a body against `StreamingServer`'s pattern incrementally, so a 32 MiB download is never
/// held in memory by the test itself.
private struct BodyVerifier: Sendable {

    private(set) var position = 0
    private(set) var isIntact = true

    mutating func consume(_ data: Data) {
        var offset = data.startIndex

        while offset < data.endIndex {
            let length = min(StreamingServer.maximumWrite, data.endIndex - offset)
            let expected = StreamingServer.slice(from: position, count: length)

            if data[offset..<offset + length] != expected {
                isIntact = false
            }

            offset += length
            position += length
        }
    }
}

/// The identity function, registered under a `Content-Encoding` no transport decodes natively,
/// so the body goes through `Internals.AsyncStream.decompressing(_:using:)`'s own decoding task
/// without its bytes changing.
private struct IdentityTestAlgorithm: Internals.DecompressionAlgorithm {

    static let contentEncoding = "x-requestdl-identity-test"

    struct Stream: Internals.DecompressorStream {
        mutating func callAsFunction(decompressing bytes: Data) throws -> Data { bytes }
        mutating func finish() throws -> Data { Data() }
    }

    var contentEncodingValue: String { Self.contentEncoding }

    func callAsFunction() throws -> any Internals.DecompressorStream { Stream() }
}

// MARK: - Server

/// A bare HTTP/1.1 server streaming `totalBytes` of a position-dependent pattern to whoever
/// connects, writing only while the socket accepts more.
///
/// Not `LocalServer`, which answers with a JSON envelope around a body it holds in memory in
/// full: what these tests need is a body far larger than anything worth holding, and a count of
/// how much of it the client has actually let through.
private final class StreamingServer: @unchecked Sendable {

    static let maximumWrite = 65_536

    /// `maximumWrite` bytes of the pattern from every possible phase, so any slice of the body is
    /// a slice of this.
    private static let pattern = Data((0..<(maximumWrite + 251)).map { UInt8(truncatingIfNeeded: $0 % 251) })

    static func slice(from position: Int, count: Int) -> Data {
        let phase = position % 251
        return pattern[phase..<phase + count]
    }

    let totalBytes: Int
    let head: String
    private(set) var port = 0

    var bytesWritten: Int {
        lock.withLock { _bytesWritten }
    }

    var isConnectionClosed: Bool {
        lock.withLock { _isConnectionClosed }
    }

    private let lock = Lock()
    private var _bytesWritten = 0
    private var _isConnectionClosed = false
    private var _channel: Channel?

    init(totalBytes: Int, headers: [(String, String)]) {
        self.totalBytes = totalBytes

        let extraHeaders = headers.map { "\($0.0): \($0.1)\r\n" }.joined()
        self.head = "HTTP/1.1 200 OK\r\nContent-Length: \(totalBytes)\r\n\(extraHeaders)\r\n"
    }

    fileprivate func bind(on group: EventLoopGroup) async throws -> Channel {
        let bootstrap = ServerBootstrap(group: group)
            // Small, fixed send buffer: keeps the kernel from absorbing a large share of the body
            // on the server's side, so the stall shows up early and unambiguously.
            .childChannelOption(ChannelOptions.socketOption(.so_sndbuf), value: 32_768)
            .childChannelInitializer { channel in
                self.lock.withLock { self._channel = channel }
                return channel.pipeline.addHandler(StreamingServerHandler(self))
            }

        let channel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
        port = channel.localAddress?.port ?? 0
        return channel
    }

    fileprivate func didWrite(_ bytes: Int) {
        lock.withLock { _bytesWritten += bytes }
    }

    fileprivate func didClose() {
        lock.withLock { _isConnectionClosed = true }
    }

    func closeConnection() {
        lock.withLock { _channel }?.close(promise: nil)
    }

    /// Waits for the count of bytes the kernel accepted to stop moving for half a second, or to
    /// reach the whole body, and returns it.
    func settledBytesWritten() async throws -> Int {
        var last = -1
        var quietPolls = 0

        for _ in 0..<3_000 {
            let current = bytesWritten

            if current == totalBytes {
                return current
            }

            if current == last {
                quietPolls += 1

                if quietPolls >= 50 {
                    return current
                }
            } else {
                last = current
                quietPolls = 0
            }

            try await _Concurrency.Task.sleep(nanoseconds: 10_000_000)
        }

        return bytesWritten
    }
}

private final class StreamingServerHandler: ChannelInboundHandler, @unchecked Sendable {

    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let server: StreamingServer
    private var didRespond = false
    private var offset = 0

    init(_ server: StreamingServer) {
        self.server = server
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        // The request itself is irrelevant: whatever arrives first is answered once.
        guard !didRespond else {
            return
        }

        didRespond = true

        let head = context.channel.allocator.buffer(string: server.head)
        context.write(wrapOutboundOut(head), promise: nil)
        pump(context: context)
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        pump(context: context)
        context.fireChannelWritabilityChanged()
    }

    func channelInactive(context: ChannelHandlerContext) {
        server.didClose()
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    private func pump(context: ChannelHandlerContext) {
        guard didRespond else {
            return
        }

        while offset < server.totalBytes, context.channel.isWritable {
            let count = min(StreamingServer.maximumWrite, server.totalBytes - offset)
            let buffer = context.channel.allocator.buffer(bytes: StreamingServer.slice(from: offset, count: count))
            offset += count

            let server = server
            context.writeAndFlush(wrapOutboundOut(buffer)).whenSuccess {
                server.didWrite(count)
            }
        }
    }
}

private func withStreamingServer<Result>(
    totalBytes: Int,
    headers: [(String, String)] = [],
    perform body: (StreamingServer) async throws -> Result
) async throws -> Result {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let server = StreamingServer(totalBytes: totalBytes, headers: headers)

    let serverChannel: Channel

    do {
        serverChannel = try await server.bind(on: group)
    } catch {
        try await group.shutdownGracefully()
        throw error
    }

    do {
        let result = try await body(server)
        server.closeConnection()
        try? await serverChannel.close()
        try await group.shutdownGracefully()
        return result
    } catch {
        server.closeConnection()
        try? await serverChannel.close()
        try await group.shutdownGracefully()
        throw error
    }
}

#endif
