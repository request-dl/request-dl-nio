//
// See LICENSE for this package's licensing information.
//

// Darwin only, like `Internals.URLSessionClient` itself. Deliberately free of NIO on both ends --
// the server below is plain BSD sockets -- so this suite also runs, and matters most, under
// `--disable-default-traits`, where `.urlSession` is the only executor there is.
#if canImport(Darwin)

import Darwin
import Foundation
import SwiftAsyncStream
import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

/// End-to-end coverage for the back pressure in `Internals.URLSessionClient`'s `SessionTask`
/// path: the `.urlSession` counterpart to `InternalsClientResponseReceiverBackPressureTests`. A
/// reader slower than the network must hold the *connection* back -- here by the body being
/// pulled from `URLSession.AsyncBytes` only as the reader drains the window -- not have the body
/// pile up in memory, and no way of abandoning such a reader may leave the request hung.
///
/// Every test observes the server rather than trusting the client's own bookkeeping alone:
/// `RawStreamingServer` writes with blocking `send(2)` into a small send buffer and counts what the
/// kernel actually accepted. If the client kept reading the socket regardless of the reader, that
/// count would race to the full body, which is exactly what each test's "the connection really
/// paused" precondition rules out. Against the `didReceive data:` delegate this path used before,
/// every one of those preconditions fails.
///
/// Unlike on the `.nio` path, the backlog in memory is not just the window: CFNetwork reads
/// ahead of `AsyncBytes` by up to about the socket's receive ceiling before it stops, and none of
/// that is visible to the window. So these tests bound the window itself tightly and the whole
/// backlog -- what the server got out minus what the reader took -- by that ceiling.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsURLSessionClientBackPressureTests {

    /// Far past the window plus anything `readAheadAllowance` allows for, so "stalled well short
    /// of this" can only mean the client stopped reading from the socket.
    private static let largeBody = 64 * 1_048_576

    private static var window: (high: Int, low: Int) {
        (Internals.FlowControlWindow.defaultHighWatermark, Internals.FlowControlWindow.defaultLowWatermark)
    }

    /// How far past the high watermark the window itself can get: the flush that crossed it (at
    /// most `Internals.URLSessionClient.maximumPendingBytes`), counted twice for a moment while
    /// `Internals.DownloadBuffer` charges what it emits before crediting what it dequeued, plus one
    /// `readingMode` chunk. `AsyncBytes` hands over nothing it wasn't asked for, so this is as
    /// tight as on the `.nio` path.
    private static let windowOvershoot = 512 * 1_024

    /// How far past what the reader took the server can get before the connection stalls:
    /// the window, plus CFNetwork's own read-ahead ahead of `AsyncBytes` (measured at about
    /// 4.5 MiB against a 4 MiB receive ceiling, with or without load), plus the server's own
    /// send buffer. Generous; the unbounded delegate reaches all of `largeBody`.
    private static let readAheadAllowance = window.high + windowOvershoot + 3 * receiveBufferCeiling

    @Test
    func slowReader_pausesTheConnectionInsteadOfBufferingTheBody() async throws {
        try await withRawStreamingServer(totalBytes: Self.largeBody) { server in
            // Given
            let (task, step) = try await startDownload(server)
            let window = try #require(step.bytes.flowControlWindowForTesting)

            var iterator = step.bytes.makeAsyncIterator()
            var verifier = BodyVerifier()

            verifier.consume(try #require(try await iterator.next()))

            // When: the reader stops.
            let written = try await server.settledBytesWritten()

            // Then: the connection paused, and the backlog held in memory stayed bounded.
            #expect(written - verifier.position <= Self.readAheadAllowance)
            #expect(window.peakBufferedBytesForTesting <= Self.window.high + Self.windowOvershoot)
            #expect(window.waitingCountForTesting == 1)

            // And once the reader resumes, the whole body arrives, intact, still within the window
            // -- over many pauses, since the reader only ever drains down to the low watermark
            // before the next one.
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
            #expect(server.acceptedConnections == 1)

            withExtendedLifetime(task) {}
        }
    }

    /// The same slow reader, with the session's delegate queue held up while the response starts
    /// streaming in, the way CPU contention holds it up.
    ///
    /// This is the condition that sank `URLSessionTask.suspend()` as a mechanism: CFNetwork fills
    /// its own buffer ahead of the stalled queue, and with nothing but `suspend()` it then went on
    /// delivering the entire body to a task reporting `.suspended`, every time. The `AsyncBytes`
    /// path has to hold regardless.
    @Test(
        .toleratingSimulatorFlake(
            "Asserts that a task is observed waiting at an exact moment, which a simulator runner starved of CPU for minutes (this test has taken over 180s there) can't promise; the other platforms are what catch a regression"
        )
    )
    func delegateQueueFallingBehind_stillPausesTheConnection() async throws {
        try await withRawStreamingServer(totalBytes: Self.largeBody) { server in
            // Given: the delegate queue blocked while the response starts streaming in.
            let (task, step) = try await startDownload(server) { client in
                client.delegateQueueForTesting.addOperation {
                    usleep(200_000)
                }
            }
            let window = try #require(step.bytes.flowControlWindowForTesting)

            var iterator = step.bytes.makeAsyncIterator()
            var verifier = BodyVerifier()

            verifier.consume(try #require(try await iterator.next()))

            // When: the reader stops.
            let written = try await server.settledBytesWritten()

            // Then
            #expect(written - verifier.position <= Self.readAheadAllowance)
            #expect(window.peakBufferedBytesForTesting <= Self.window.high + Self.windowOvershoot)
            #expect(window.waitingCountForTesting == 1)

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
            #expect(server.acceptedConnections == 1)

            withExtendedLifetime(task) {}
        }
    }

    /// Manual decompression's decoding task reads `Internals.DownloadBuffer`'s stream as fast as
    /// it can decode. It meters its own output with a window of its own, so the actual reader's
    /// pace has to reach all the way back through it to the connection.
    @Test
    func slowReaderBehindManualDecompression_stillPausesTheConnection() async throws {
        try await withRawStreamingServer(
            totalBytes: Self.largeBody,
            headers: [("Content-Encoding", IdentityTestAlgorithm.contentEncoding)]
        ) { server in
            // Given
            let (task, step) = try await startDownload(
                server,
                decompression: .enabled(algorithms: [IdentityTestAlgorithm()], limit: .none)
            )

            // The decoder's own window, not the pump's.
            let window = try #require(step.bytes.flowControlWindowForTesting)

            var iterator = step.bytes.makeAsyncIterator()
            var verifier = BodyVerifier()

            verifier.consume(try #require(try await iterator.next()))

            // When
            let written = try await server.settledBytesWritten()

            // Then: both windows' worth on top of the usual allowance.
            #expect(written - verifier.position <= Self.readAheadAllowance + Self.window.high + Self.windowOvershoot)
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

    /// A `.length(n)` chunk bigger than the whole window can only complete with more input. The
    /// bytes waiting for it are credited back as they enter `Internals.DownloadBuffer`'s
    /// accumulator; counting them instead would pause the pump with nothing the reader could ever
    /// drain, and this would hang.
    @Test
    func chunkLargerThanTheWindow_stillCompletes() async throws {
        let totalBytes = 16 * 1_048_576
        let chunkLength = 3 * 1_048_576

        try await withRawStreamingServer(totalBytes: totalBytes) { server in
            // Given
            let (task, step) = try await startDownload(server, readingMode: .length(chunkLength))

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

    // MARK: - Nothing held back that the reader asked for

    /// `AsyncBytes` hands out single bytes, and the pump batches them before handing them on. A
    /// batch must never hold back a chunk `readingMode` already completed: here the server stops
    /// right after the first separator, and the first line has to reach the reader anyway, rather
    /// than wait for a batch the rest of the body would have to fill.
    @Test
    func separatorChunk_reachesTheReaderWithoutWaitingForMoreOfTheBody() async throws {
        // The server's pattern is `position % 251`, so a lone `250` ends every 251-byte line.
        try await withRawStreamingServer(totalBytes: 1_048_576, pauseAfter: 300) { server in
            // Given
            let (task, step) = try await startDownload(server, readingMode: .separator([250]))

            // When
            let first = try await completing(within: 10) {
                var iterator = step.bytes.makeAsyncIterator()
                return try await iterator.next()
            }

            // Then
            #expect(first == RawStreamingServer.slice(from: 0, count: 251))
            #expect(server.bytesWritten == 300)

            server.resumeWriting()
            withExtendedLifetime(task) {}
        }
    }

    /// The `.length(n)` counterpart to the test above.
    @Test
    func lengthChunk_reachesTheReaderWithoutWaitingForMoreOfTheBody() async throws {
        try await withRawStreamingServer(totalBytes: 1_048_576, pauseAfter: 150) { server in
            // Given
            let (task, step) = try await startDownload(server, readingMode: .length(100))

            // When
            let first = try await completing(within: 10) {
                var iterator = step.bytes.makeAsyncIterator()
                return try await iterator.next()
            }

            // Then
            #expect(first == RawStreamingServer.slice(from: 0, count: 100))
            #expect(server.bytesWritten == 150)

            server.resumeWriting()
            withExtendedLifetime(task) {}
        }
    }

    // MARK: - Nothing hangs

    /// Nobody ever reads the body, and the response is dropped with the connection paused. The
    /// seed going away must cancel the request and release the window, not leave it holding its
    /// connection (and the client's throttle slot) for good.
    @Test
    func readerNeverStarts_droppingTheResponse_cancelsTheRequest() async throws {
        try await withRawStreamingServer(totalBytes: Self.largeBody) { server in
            // Given
            let window: Internals.FlowControlWindow
            let client = try Internals.URLSessionClient(configuration: .ephemeral)

            do {
                let (task, step) = try await startDownload(server, client: client)
                window = try #require(step.bytes.flowControlWindowForTesting)

                let written = try await server.settledBytesWritten()
                #expect(written <= Self.readAheadAllowance)
                #expect(window.waitingCountForTesting == 1)

                // When: everything goes out of scope here.
                withExtendedLifetime((task, step)) {}
            }

            // Then
            try await eventually { window.isReleasedForTesting && window.waitingCountForTesting == 0 }
            try await eventually { server.isConnectionClosed }
            try await eventually { !client.isRunning }
            #expect(server.bytesWritten < Self.largeBody)
        }
    }

    /// The reader reads a little and then goes away for good -- a `break`, or the task running
    /// the loop being cancelled -- while the response itself is kept. Its iterator going away
    /// releases the window, so the request runs to completion instead of staying paused forever
    /// for a reader that can never come back.
    @Test
    func readerStopsAndItsTaskIsCancelled_letsTheRequestFinish() async throws {
        try await withRawStreamingServer(totalBytes: Self.largeBody) { server in
            // Given
            let client = try Internals.URLSessionClient(configuration: .ephemeral)
            let (task, step) = try await startDownload(server, client: client)
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
            #expect(written <= Self.readAheadAllowance)
            #expect(window.waitingCountForTesting == 1)

            // When
            reader.cancel()
            _ = await reader.result

            // Then
            try await eventually { window.isReleasedForTesting }
            try await eventually(timeout: 60) { server.bytesWritten == Self.largeBody }
            try await eventually { !client.isRunning }

            withExtendedLifetime(task) {}
        }
    }

    /// The caller cancels the request while the pump waits behind a reader that is still there.
    /// The window is released right away, by the cancellation itself, and the reader then gets
    /// the failure instead of waiting for bytes that will never come.
    @Test
    func requestCancelledWhilePaused_failsTheReaderInsteadOfHanging() async throws {
        try await withRawStreamingServer(totalBytes: Self.largeBody) { server in
            // Given
            let client = try Internals.URLSessionClient(configuration: .ephemeral)
            let (task, step) = try await startDownload(server, client: client)
            let window = try #require(step.bytes.flowControlWindowForTesting)

            var iterator = step.bytes.makeAsyncIterator()
            _ = try await iterator.next()

            let written = try await server.settledBytesWritten()
            #expect(written <= Self.readAheadAllowance)
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
            try await eventually { !client.isRunning }
        }
    }

    /// The same cancellation, but with the server already done: the whole (small) body has been
    /// written, most of it -- its end included -- sitting unread in the sockets and CFNetwork
    /// behind the paused pump. On the `.nio` path this was the state where AsyncHTTPClient held
    /// the cancellation back until the paused part completed. The guarantee here has to be the
    /// same: the window released by the cancellation itself, and the reader never handed a clean
    /// end of a truncated body. A complete, intact body is an acceptable answer (whatever
    /// `URLSession` already handed over before the cancellation landed); a *short* one ending
    /// cleanly never is.
    @Test
    func requestCancelledWithTheRestOfTheBodyAlreadySent_neverEndsATruncatedBodyCleanly() async throws {
        let totalBytes = 458_752

        try await withRawStreamingServer(totalBytes: totalBytes) { server in
            // Given: nobody reads, so the first flush overfills a tiny window and pauses the
            // pump, while the body is small enough for the server to get all of it out anyway.
            let (task, step) = try await startDownload(
                server,
                readingMode: .length(1_024),
                flowControl: .init(highWatermark: 1_024, lowWatermark: 512)
            )
            let window = try #require(step.bytes.flowControlWindowForTesting)

            try await eventually { server.bytesWritten == totalBytes }
            try await eventually { window.waitingCountForTesting == 1 }

            // When
            task.seed()

            // Then: released right away, without the reader doing anything at all.
            #expect(window.isReleasedForTesting)
            #expect(window.waitingCountForTesting == 0)

            let outcome = try await completing(within: 30) {
                var verifier = BodyVerifier()

                do {
                    for try await chunk in step.bytes {
                        verifier.consume(chunk)
                    }

                    return verifier.isIntact && verifier.position == totalBytes ? "complete" : "truncated"
                } catch {
                    return "failed"
                }
            }

            #expect(outcome == "failed" || outcome == "complete")
        }
    }

    /// Cancelled before the response head ever arrives: `bytes(for:delegate:)` hasn't handed its
    /// task over yet, so only cancelling the exchange itself can reach it. The head must fail,
    /// and the client must let go of the request.
    @Test
    func requestCancelledBeforeTheHead_failsTheHeadAndReleasesTheClient() async throws {
        try await withRawStreamingServer(totalBytes: Self.largeBody, holdHead: true) { server in
            // Given
            let client = try Internals.URLSessionClient(configuration: .ephemeral)
            let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/"))

            let task = try await client.execute(
                request: URLRequest(url: url),
                readingMode: .length(65_536),
                uploadingBytes: .zero,
                decompression: .disabled,
                cache: nil,
                logger: nil
            )

            try await eventually { server.acceptedConnections == 1 }
            #expect(client.isRunning)

            // When
            task.seed()

            // Then
            let outcome = try await completing(within: 30) {
                do {
                    for try await _ in task.response {}
                    return "finished"
                } catch {
                    return "failed"
                }
            }

            #expect(outcome == "failed")
            try await eventually { !client.isRunning }
            try await eventually { server.isConnectionClosed }
        }
    }

    /// The connection drops mid-body while the reader has stopped. Reading down what was
    /// already buffered has to surface the failure, not wait forever.
    @Test
    func connectionDropsWhilePaused_failsTheReaderInsteadOfHanging() async throws {
        try await withRawStreamingServer(totalBytes: Self.largeBody) { server in
            // Given
            let client = try Internals.URLSessionClient(configuration: .ephemeral)
            let (task, step) = try await startDownload(server, client: client)
            let window = try #require(step.bytes.flowControlWindowForTesting)

            var iterator = step.bytes.makeAsyncIterator()
            _ = try await iterator.next()

            let written = try await server.settledBytesWritten()
            #expect(written <= Self.readAheadAllowance)
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
            try await eventually { !client.isRunning }

            withExtendedLifetime(task) {}
        }
    }

    // MARK: - Known trade-off

    /// Pins down a behaviour change, not a goal: a response that is held back receives nothing
    /// for as long as the reader stays away, and `URLSession` times a request out under
    /// `URLSessionConfiguration.timeoutIntervalForRequest` once it has received nothing for that
    /// long. So a reader that stops for longer than the request timeout, with more than the
    /// window (plus CFNetwork's read-ahead) left, fails with `.timedOut` once it reads again,
    /// where the unbounded delegate used to buffer the whole body for it.
    /// `URLSessionConfiguration`'s default is 60 seconds; `URLSession.bytes(for:)` used on its own
    /// behaves exactly the same way.
    ///
    /// Nothing fails *while* the reader is away: the task keeps reporting `.running`, and the
    /// timeout only surfaces through the body once reading resumes. What matters here is that it
    /// then *fails*, promptly and visibly, instead of hanging or handing over a truncated body as
    /// if it were whole.
    @Test
    func readerSlowerThanTheRequestTimeout_failsWithATimeoutOnceItReadsAgain() async throws {
        try await withRawStreamingServer(totalBytes: Self.largeBody) { server in
            // Given
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 1

            let client = try Internals.URLSessionClient(configuration: configuration)
            let (task, step) = try await startDownload(server, client: client)
            let window = try #require(step.bytes.flowControlWindowForTesting)

            var iterator = step.bytes.makeAsyncIterator()
            _ = try await iterator.next()

            let written = try await server.settledBytesWritten()
            #expect(written <= Self.readAheadAllowance)

            // When: the reader stays away for longer than the request timeout.
            try await _Concurrency.Task.sleep(nanoseconds: 3_000_000_000)
            #expect(window.waitingCountForTesting == 1)

            // Then
            let outcome = try await completing(within: 30) { [iterator] in
                var iterator = iterator

                do {
                    while try await iterator.next() != nil {}
                    return "finished"
                } catch let error as URLError {
                    return "failed: \(error.code.rawValue)"
                } catch {
                    return "failed: \(error)"
                }
            }

            #expect(outcome == "failed: \(URLError.Code.timedOut.rawValue)")
            #expect(server.bytesWritten < Self.largeBody)
            try await eventually { window.isReleasedForTesting }
            try await eventually { !client.isRunning }

            withExtendedLifetime(task) {}
        }
    }

    // MARK: - Request bodies

    /// A body past `Internals.URLSessionUploadFile.inMemoryThreshold` spills to a temporary file,
    /// and reaches the wire as a stream over that file with its exact `Content-Length`. The file
    /// has to outlive the upload itself -- a redirect or retry resends from it for as long as the
    /// exchange runs -- and be gone once the exchange ends.
    @Test
    func spilledUpload_isSentWhole_andItsFileRemovedOnlyOnceTheExchangeEnds() async throws {
        // An odd size, so the spilled file is recognizable among whatever else is in the shared
        // temporary directory.
        let uploadSize = Internals.URLSessionUploadFile.inMemoryThreshold + 1_048_576 + 17
        let payload = Data((0..<uploadSize).map { UInt8(truncatingIfNeeded: $0 &* 7) })

        try await withRawStreamingServer(totalBytes: Self.largeBody) { server in
            // Given
            let client = try Internals.URLSessionClient(configuration: .ephemeral)
            let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/upload"))
            var request = URLRequest(url: url)
            request.httpMethod = "POST"

            let before = spilledBufferFiles(ofSize: uploadSize)

            let task = try await client.execute(
                request: request,
                streaming: chunkedBody(payload),
                readingMode: .length(65_536),
                uploadingBytes: uploadSize,
                decompression: .disabled,
                cache: nil,
                logger: nil
            )

            let step = try await downloadStep(of: task)

            // Then: the whole body arrived, framed with its exact length rather than chunked.
            #expect(server.requests.map(\.bodyLength) == [uploadSize])
            #expect(server.requests.map(\.contentLength) == [uploadSize])
            #expect(server.requests.map(\.isChunked) == [false])

            // And while the response is still being held back, the spilled file is still there.
            _ = try await server.settledBytesWritten()
            #expect(spilledBufferFiles(ofSize: uploadSize).subtracting(before).count == 1)

            // When: the exchange ends.
            let received = try await completing(within: 60) {
                var received = 0
                for try await chunk in step.bytes {
                    received += chunk.count
                }
                return received
            }

            // Then
            #expect(received == Self.largeBody)
            try await eventually { spilledBufferFiles(ofSize: uploadSize).subtracting(before).isEmpty }
            try await eventually { !client.isRunning }
        }
    }

    /// A `Payload(url:)` body is uploaded straight from the caller's own file. A 307 redirect
    /// makes the request go out again with the same body: the destination has to get all of it,
    /// and the caller's file has to be left alone afterwards.
    ///
    /// Handled entirely by `TaskDelegate.completeRedirect(with:_:)`/`takePendingManualBodyRedirect()`
    /// -- a manual resend with a fresh stream over `bodyFileURL`, not `URLSession`'s own
    /// `needNewBodyStream`. Verified directly, on watchOS specifically: `URLSession` there calls
    /// neither `needNewBodyStream` for this resend nor honours a stream attached to the request
    /// returned from `willPerformHTTPRedirection`, and instead resends the *original* request's
    /// already-exhausted stream, silently sending an empty body. Every other platform tested
    /// (macOS, iOS, iPadOS, tvOS, Catalyst) does call `needNewBodyStream` correctly on its own --
    /// this test would still pass either way, since the manual path runs uniformly regardless.
    @Test
    func existingFileUpload_resentOnA307_arrivesWholeAtTheDestination() async throws {
        let payload = Data((0..<3_000_001).map { UInt8(truncatingIfNeeded: $0 &* 13) })

        try await withTemporaryFileURL("existing-upload.bin") { fileURL in
            try payload.write(to: fileURL)

            try await withRawStreamingServer(totalBytes: 1_048_576, redirectFirstRequest: true) { server in
                // Given
                let client = try Internals.URLSessionClient(configuration: .ephemeral)
                let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/upload"))
                var request = URLRequest(url: url)
                request.httpMethod = "POST"

                let progress = LockedValueBox<[Int]>([])

                // When
                let task = try await client.execute(
                    request: request,
                    streaming: chunkedBody(Data()),
                    readingMode: .length(65_536),
                    uploadingBytes: payload.count,
                    decompression: .disabled,
                    cache: nil,
                    logger: nil,
                    existingUploadFile: fileURL
                )

                var received = 0

                for try await step in task.response {
                    switch step {
                    case .upload(let upload):
                        progress.withLockedValue { $0.append(upload.chunkSize) }
                    case .download(let download):
                        for try await chunk in download.bytes {
                            received += chunk.count
                        }
                    }
                }

                // Then
                #expect(received == 1_048_576)
                #expect(server.requests.map(\.path) == ["/upload", "/final"])
                #expect(server.requests.map(\.bodyLength) == [payload.count, payload.count])
                #expect(server.requests.map(\.contentLength) == [payload.count, payload.count])
                #expect(progress.withLockedValue { $0 }.reduce(0, +) >= payload.count)
                #expect(try Data(contentsOf: fileURL) == payload)
            }
        }
    }

    /// A `Payload(url:)` body whose file is gone by the time the request runs fails before
    /// anything is sent. (`uploadTask(with:fromFile:)`, which this path used before, sent it as
    /// an empty body and reported success.)
    @Test
    func existingFileUpload_whenTheFileIsMissing_failsWithoutSendingAnything() async throws {
        try await withRawStreamingServer(totalBytes: 1_024) { server in
            // Given
            let client = try Internals.URLSessionClient(configuration: .ephemeral)
            let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/upload"))
            var request = URLRequest(url: url)
            request.httpMethod = "POST"

            let missing = temporaryDirectoryURL.appendingPathComponent("missing-\(UUID().uuidString).bin")

            // When
            await #expect(throws: (any Error).self) {
                _ = try await client.execute(
                    request: request,
                    streaming: chunkedBody(Data()),
                    readingMode: .length(65_536),
                    uploadingBytes: .zero,
                    decompression: .disabled,
                    cache: nil,
                    logger: nil,
                    existingUploadFile: missing
                )
            }

            // Then
            #expect(!client.isRunning)
            #expect(server.acceptedConnections == 0)
        }
    }
}

// MARK: - Client

/// `net.inet.tcp.autorcvbufmax`: the most the kernel lets a single TCP socket's receive buffer
/// grow to, and so roughly the most CFNetwork reads off one connection ahead of `AsyncBytes`.
/// Falls back to macOS's long-standing default if the lookup fails.
private let receiveBufferCeiling: Int = {
    var value: UInt64 = 0
    var size = MemoryLayout<UInt64>.size

    guard sysctlbyname("net.inet.tcp.autorcvbufmax", &value, &size, nil, 0) == 0 else {
        return 4 * 1_048_576
    }

    // Whichever width the kernel reports it in: `value` started zeroed, so a 32-bit answer lands
    // in its low half on every platform this runs on (all little-endian).
    let ceiling = size == MemoryLayout<UInt32>.size ? Int(UInt32(truncatingIfNeeded: value)) : Int(value)
    return ceiling > 0 ? ceiling : 4 * 1_048_576
}()

/// Starts a GET against `server` and returns once the response head is in, before any of the body
/// has been read.
private func startDownload(
    _ server: RawStreamingServer,
    client: Internals.URLSessionClient? = nil,
    readingMode: Internals.DownloadStep.ReadingMode = .length(65_536),
    decompression: Internals.Decompression = .disabled,
    flowControl: Internals.FlowControlWindow = .init(),
    beforeStarting prepare: (Internals.URLSessionClient) -> Void = { _ in }
) async throws -> (SessionTask, Internals.DownloadStep) {
    let client = try client ?? Internals.URLSessionClient(configuration: .ephemeral)
    let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/"))

    prepare(client)

    let task = try await client.execute(
        request: URLRequest(url: url),
        readingMode: readingMode,
        uploadingBytes: .zero,
        decompression: decompression,
        cache: nil,
        logger: nil,
        flowControl: flowControl
    )

    return (task, try await downloadStep(of: task))
}

private func downloadStep(of task: SessionTask) async throws -> Internals.DownloadStep {
    for try await step in task.response {
        if case .download(let download) = step {
            return download
        }
    }

    throw AnyError()
}

/// `data` as an upload body sequence, in 64 KiB pieces.
private func chunkedBody(_ data: Data) -> AsyncStream<Internals.Bytes> {
    let (stream, continuation) = AsyncStream<Internals.Bytes>.makeStream()

    for start in Swift.stride(from: 0, to: data.count, by: 65_536) {
        continuation.yield(Internals.Bytes(data[start..<Swift.min(start + 65_536, data.count)]))
    }

    continuation.finish()
    return stream
}

/// Every `Internals.FileBufferURL.temporaryURL`-named file of exactly `size` bytes currently in
/// the temporary directory.
private func spilledBufferFiles(ofSize size: Int) -> Set<String> {
    let directory = temporaryDirectoryURL.path
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []

    return Set(
        names.filter { name in
            guard name.hasSuffix(".buffer") else {
                return false
            }

            let attributes = try? FileManager.default.attributesOfItem(atPath: directory + "/" + name)
            return (attributes?[.size] as? NSNumber)?.intValue == size
        }
    )
}

/// Checks a body against `RawStreamingServer`'s pattern incrementally, so a 64 MiB download is
/// never held in memory by the test itself.
private struct BodyVerifier: Sendable {

    private(set) var position = 0
    private(set) var isIntact = true

    mutating func consume(_ data: Data) {
        var offset = data.startIndex

        while offset < data.endIndex {
            let length = min(RawStreamingServer.maximumWrite, data.endIndex - offset)
            let expected = RawStreamingServer.slice(from: position, count: length)

            if data[offset..<offset + length] != expected {
                isIntact = false
            }

            offset += length
            position += length
        }
    }
}

/// The identity function, registered under a `Content-Encoding` CFNetwork doesn't decode, so the
/// body goes through `Internals.AsyncStream.decompressing(_:using:)`'s own decoding task without
/// its bytes changing.
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

/// A bare HTTP/1.1 server on plain BSD sockets, streaming `totalBytes` of a position-dependent
/// pattern to whoever connects, with blocking `send(2)` calls on a thread of its own.
///
/// Not `LocalServer`, which answers with a JSON envelope around a body it holds in memory in
/// full, and not the NIO server `InternalsClientResponseReceiverBackPressureTests` uses, which
/// wouldn't exist under `--disable-default-traits`. What these tests need is a body far larger
/// than anything worth holding, and an exact count of how much of it the client's kernel has
/// actually let through: `send(2)` only returns once the kernel took the bytes, and with a small
/// send buffer, it stops returning soon after the client stops reading from its socket.
///
/// Reads (and records) a request body framed by `Content-Length` or chunked encoding before
/// answering, can answer the first request with a 307 to `/final` instead (`redirectFirstRequest`),
/// can stop writing after a given number of body bytes until told to go on (`pauseAfter`), and can
/// withhold the response head entirely (`holdHead`).
private final class RawStreamingServer: @unchecked Sendable {

    struct ReceivedRequest: Sendable {
        let path: String
        let contentLength: Int?
        let isChunked: Bool
        let bodyLength: Int
    }

    static let maximumWrite = 65_536

    /// `maximumWrite` bytes of the pattern from every possible phase, so any slice of the body is
    /// a slice of this.
    private static let pattern = Data((0..<(maximumWrite + 251)).map { UInt8(truncatingIfNeeded: $0 % 251) })

    static func slice(from position: Int, count: Int) -> Data {
        let phase = position % 251
        return pattern[phase..<phase + count]
    }

    let totalBytes: Int
    let port: Int

    var bytesWritten: Int {
        lock.withLock { _bytesWritten }
    }

    var isConnectionClosed: Bool {
        lock.withLock { _isConnectionClosed }
    }

    var acceptedConnections: Int {
        lock.withLock { _acceptedConnections }
    }

    var requests: [ReceivedRequest] {
        lock.withLock { _requests }
    }

    fileprivate var isFinished: Bool {
        lock.withLock { _isFinished }
    }

    private let head: [UInt8]
    private let listener: Int32
    private let redirectFirstRequest: Bool
    private let pauseAfter: Int?
    private let holdHead: Bool
    private let lock = Lock()

    private var _bytesWritten = 0
    private var _isConnectionClosed = false
    private var _acceptedConnections = 0
    private var _connection: Int32 = -1
    private var _isStopped = false
    private var _isFinished = false
    private var _isWritingResumed = false
    private var _requests: [ReceivedRequest] = []

    init(
        totalBytes: Int,
        headers: [(String, String)],
        redirectFirstRequest: Bool,
        pauseAfter: Int?,
        holdHead: Bool
    ) throws {
        self.totalBytes = totalBytes
        self.redirectFirstRequest = redirectFirstRequest
        self.pauseAfter = pauseAfter
        self.holdHead = holdHead

        // `Content-Type` matters: without one, CFNetwork holds the response back to sniff a MIME
        // type from the first 512 body bytes, so a server that pauses before sending that many
        // never gets a response through at all.
        let extraHeaders = headers.map { "\($0.0): \($0.1)\r\n" }.joined()
        let head =
            "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\n"
            + "Content-Length: \(totalBytes)\r\n\(extraHeaders)\r\n"
        self.head = Array(head.utf8)

        let listener = socket(AF_INET, SOCK_STREAM, 0)
        guard listener >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        address.sin_port = 0

        var length = socklen_t(MemoryLayout<sockaddr_in>.size)

        let isListening = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(listener, $0, length) == 0 && listen(listener, 8) == 0 && getsockname(listener, $0, &length) == 0
            }
        }

        guard isListening else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            close(listener)
            throw error
        }

        self.listener = listener
        self.port = Int(UInt16(bigEndian: address.sin_port))

        Thread.detachNewThread { [self] in
            run()
        }
    }

    /// Drops the current connection from the server's side, the way a server or a middlebox
    /// giving up mid-response would. Wakes a blocked `send(2)`; the serving thread closes the
    /// descriptor itself, so it's never reused out from under that call.
    func closeConnection() {
        let connection = lock.withLock { _connection }

        if connection >= 0 {
            shutdown(connection, SHUT_RDWR)
        }
    }

    /// Lets a server paused by `pauseAfter` (or holding its head back) carry on.
    func resumeWriting() {
        lock.withLock { _isWritingResumed = true }
    }

    fileprivate func stop() {
        lock.withLock {
            _isStopped = true
            _isWritingResumed = true
        }
        closeConnection()
    }

    /// Waits for the count of bytes the kernel accepted to stop moving for half a second -- or to
    /// reach the whole body -- and returns it.
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

    // MARK: - Serving thread

    private func run() {
        defer {
            close(listener)
            lock.withLock { _isFinished = true }
        }

        while !lock.withLock({ _isStopped }) {
            // Polled rather than a bare blocking `accept(2)`, so `stop()` is noticed without
            // having to close the listener out from under a call still using it.
            var descriptor = pollfd(fd: listener, events: Int16(POLLIN), revents: 0)

            guard poll(&descriptor, 1, 50) > 0 else {
                continue
            }

            let connection = accept(listener, nil, nil)

            guard connection >= 0 else {
                continue
            }

            serve(connection)
        }
    }

    private func serve(_ connection: Int32) {
        let isStopped = lock.withLock { () -> Bool in
            _acceptedConnections += 1
            _connection = connection
            _isConnectionClosed = false
            return _isStopped
        }

        defer {
            lock.withLock {
                _connection = -1
                _isConnectionClosed = true
            }

            close(connection)
        }

        guard !isStopped else {
            return
        }

        var enabled: Int32 = 1
        setsockopt(connection, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))

        // Small, fixed send buffer: keeps the kernel from absorbing a large share of the body on
        // the server's side, so the stall shows up early and unambiguously.
        var sendBuffer: Int32 = 32_768
        setsockopt(connection, SOL_SOCKET, SO_SNDBUF, &sendBuffer, socklen_t(MemoryLayout<Int32>.size))

        var reader = RequestReader(connection: connection)

        guard let request = reader.readRequest() else {
            return
        }

        let isFirstRequest = lock.withLock { () -> Bool in
            _requests.append(request)
            return _requests.count == 1
        }

        if redirectFirstRequest && isFirstRequest {
            let redirect =
                "HTTP/1.1 307 Temporary Redirect\r\n"
                + "Location: /final\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            _ = sendAll(connection, Array(redirect.utf8), counted: false)
            return
        }

        if holdHead, !waitUntilResumed(connection) {
            return
        }

        guard sendAll(connection, head, counted: false) else {
            return
        }

        var offset = 0

        while offset < totalBytes {
            var count = min(Self.maximumWrite, totalBytes - offset)

            if let pauseAfter, offset < pauseAfter {
                count = min(count, pauseAfter - offset)
            }

            guard sendAll(connection, Array(Self.slice(from: offset, count: count)), counted: true) else {
                return
            }

            offset += count

            if let pauseAfter, offset == pauseAfter, !waitUntilResumed(connection) {
                return
            }
        }

        // Whole body written: wait for the client to close its end (or for `stop()`), so
        // `isConnectionClosed` means the same thing whether or not the body got out in full.
        var byte: UInt8 = 0
        while recv(connection, &byte, 1, 0) > 0 {}
    }

    /// Waits for `resumeWriting()`, or for the client to close its end.
    ///
    /// - Returns: `false` if the client closed its end first.
    private func waitUntilResumed(_ connection: Int32) -> Bool {
        while !lock.withLock({ _isWritingResumed }) {
            var descriptor = pollfd(fd: connection, events: Int16(POLLIN), revents: 0)

            if poll(&descriptor, 1, 10) > 0 {
                var byte: UInt8 = 0

                // Nothing else is expected from the client here, so a readable socket that has
                // nothing to read means it closed.
                if recv(connection, &byte, 1, MSG_PEEK) <= 0 {
                    return false
                }
            }
        }

        return true
    }

    private func sendAll(_ connection: Int32, _ bytes: [UInt8], counted: Bool) -> Bool {
        var offset = 0

        while offset < bytes.count {
            let sent = bytes.withUnsafeBytes {
                send(connection, $0.baseAddress! + offset, bytes.count - offset, 0)
            }

            guard sent > 0 else {
                return false
            }

            offset += sent

            if counted {
                lock.withLock { _bytesWritten += sent }
            }
        }

        return true
    }
}

/// Reads one request -- head, then a body framed by `Content-Length` or chunked encoding -- off a
/// blocking socket.
private struct RequestReader {

    let connection: Int32
    private var buffer: [UInt8] = []

    init(connection: Int32) {
        self.connection = connection
    }

    mutating func readRequest() -> RawStreamingServer.ReceivedRequest? {
        guard let head = readHead() else {
            return nil
        }

        let lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.first?.split(separator: " ") ?? []
        let path = requestLine.count > 1 ? String(requestLine[1]) : ""

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let contentLength = headers["content-length"].flatMap { Int($0) }
        let isChunked = headers["transfer-encoding"]?.lowercased() == "chunked"

        let bodyLength: Int
        if let contentLength {
            guard skip(contentLength) else { return nil }
            bodyLength = contentLength
        } else if isChunked {
            guard let length = skipChunkedBody() else { return nil }
            bodyLength = length
        } else {
            bodyLength = 0
        }

        return .init(path: path, contentLength: contentLength, isChunked: isChunked, bodyLength: bodyLength)
    }

    private mutating func fill() -> Bool {
        var chunk = [UInt8](repeating: 0, count: 65_536)
        let count = recv(connection, &chunk, chunk.count, 0)

        guard count > 0 else {
            return false
        }

        buffer += chunk[0..<count]
        return true
    }

    private mutating func readHead() -> String? {
        let terminator: [UInt8] = Array("\r\n\r\n".utf8)

        while true {
            if let range = firstRange(of: terminator) {
                let head = String(decoding: buffer[0..<range.lowerBound], as: UTF8.self)
                buffer.removeFirst(range.upperBound)
                return head
            }

            guard fill() else {
                return nil
            }
        }
    }

    private mutating func readLine() -> String? {
        let terminator: [UInt8] = Array("\r\n".utf8)

        while true {
            if let range = firstRange(of: terminator) {
                let line = String(decoding: buffer[0..<range.lowerBound], as: UTF8.self)
                buffer.removeFirst(range.upperBound)
                return line
            }

            guard fill() else {
                return nil
            }
        }
    }

    private mutating func skip(_ count: Int) -> Bool {
        var remaining = count

        while remaining > 0 {
            if buffer.isEmpty {
                guard fill() else { return false }
            }

            let taken = min(remaining, buffer.count)
            buffer.removeFirst(taken)
            remaining -= taken
        }

        return true
    }

    private mutating func skipChunkedBody() -> Int? {
        var total = 0

        while true {
            guard
                let line = readLine(),
                let size = Int(line.split(separator: ";").first.map(String.init) ?? "", radix: 16)
            else {
                return nil
            }

            if size == .zero {
                while let trailer = readLine(), !trailer.isEmpty {}
                return total
            }

            guard skip(size), readLine() != nil else {
                return nil
            }

            total += size
        }
    }

    private func firstRange(of pattern: [UInt8]) -> Range<Int>? {
        guard buffer.count >= pattern.count else {
            return nil
        }

        for start in 0...(buffer.count - pattern.count) {
            let candidate = start..<start + pattern.count

            if buffer[candidate].elementsEqual(pattern) {
                return candidate
            }
        }

        return nil
    }
}

private func withRawStreamingServer<Result>(
    totalBytes: Int,
    headers: [(String, String)] = [],
    redirectFirstRequest: Bool = false,
    pauseAfter: Int? = nil,
    holdHead: Bool = false,
    perform body: (RawStreamingServer) async throws -> Result
) async throws -> Result {
    let server = try RawStreamingServer(
        totalBytes: totalBytes,
        headers: headers,
        redirectFirstRequest: redirectFirstRequest,
        pauseAfter: pauseAfter,
        holdHead: holdHead
    )

    do {
        let result = try await body(server)
        server.stop()
        try await eventually { server.isFinished }
        return result
    } catch {
        server.stop()
        try? await eventually { server.isFinished }
        throw error
    }
}

#endif
