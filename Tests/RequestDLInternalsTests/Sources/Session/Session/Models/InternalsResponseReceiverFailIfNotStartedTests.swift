//
// See LICENSE for this package's licensing information.
//

// `failIfNotStarted(_:)` is what the executor falls back on when AsyncHTTPClient fails a task without
// telling the delegate: a pre-flight rejection, or a request body stream that finishes after the response
// was received and the connection is gone (`RequestBag.finishRequestBodyStream`). These tests drive the
// receivers with a real `HTTPClient` against a scripted socket that holds the exchange open, then call
// `failIfNotStarted(_:)` themselves, which is exactly what the executor does when the task future fails.
// The race that triggers it in production is timing dependent and is not reproduced here: what is pinned
// down is what the receivers do once it has happened.
#if canImport(NIOCore)

import AsyncHTTPClient
import NIOCore
import NIOPosix
import SwiftAsyncStream
import Testing

@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct InternalsResponseReceiverFailIfNotStartedTests {

    // MARK: - ClientResponseReceiver

    @Test(.timeLimit(.minutes(1)))
    func clientReceiver_endsAnExchangeWhoseHeadWasReceived() async throws {
        try await withHTTPClient(.original(length: 100, sent: 0)) { url, httpClient in
            // Given: the head is delivered, no body part is.
            let fixture = await ClientFixture(url: url)
            let task = httpClient.execute(request: try .init(url: url), delegate: fixture.receiver)

            for try await _ in fixture.head {
                break
            }

            // When
            fixture.receiver.failIfNotStarted(TestFailure())

            // Then: the body fails instead of waiting for a delegate call that never comes.
            await #expect(throws: TestFailure.self) {
                for try await _ in fixture.download.stream {}
            }

            withExtendedLifetime(task) {}
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func clientReceiver_endsAnExchangeWhoseBodyHadStarted() async throws {
        try await withHTTPClient(.original(length: 100, sent: 10)) { url, httpClient in
            // Given: the head and the first part of the body (one whole chunk) are delivered.
            let fixture = await ClientFixture(url: url)
            let task = httpClient.execute(request: try .init(url: url), delegate: fixture.receiver)

            var body = fixture.download.stream.makeAsyncIterator()
            let first = try await body.next()
            #expect(first?.readableBytes == 10)

            // When
            fixture.receiver.failIfNotStarted(TestFailure())

            // Then: what was delivered stays delivered, and the rest of the body fails instead of waiting.
            await #expect(throws: TestFailure.self) {
                while try await body.next() != nil {}
            }

            withExtendedLifetime(task) {}
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func clientReceiver_leavesAnExchangeTheDelegateWasToldTheEndOf() async throws {
        try await withHTTPClient(.original(length: 10, sent: 10)) { url, httpClient in
            // Given: `didFinishRequest` ran, with its body still unread.
            let fixture = await ClientFixture(url: url)
            let task = httpClient.execute(request: try .init(url: url), delegate: fixture.receiver)
            try await task.futureResult.get()

            // When
            fixture.receiver.failIfNotStarted(TestFailure())

            // Then: the body reads to its end, not to the error.
            var received = 0
            for try await chunk in fixture.download.stream {
                received += chunk.readableBytes
            }

            #expect(received == 10)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func clientReceiver_leavesAnExchangeThatAlreadyFailed() async throws {
        try await withHTTPClient(.original(length: 100, sent: 10, closes: true)) { url, httpClient in
            // Given: the connection dropped mid-body, and `didReceiveError` ran.
            let fixture = await ClientFixture(url: url)
            let task = httpClient.execute(request: try .init(url: url), delegate: fixture.receiver)
            await #expect(throws: (any Error).self) { try await task.futureResult.get() }

            // When
            fixture.receiver.failIfNotStarted(TestFailure())

            // Then: the error the body reports is the first one.
            var thrown: (any Error)?

            do {
                for try await _ in fixture.download.stream {}
            } catch {
                thrown = error
            }

            #expect(thrown != nil)
            #expect(!(thrown is TestFailure))
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func clientReceiver_leavesAnExchangeAReconnectionTookOver() async throws {
        try await withHTTPClient(.original(length: 100, sent: 10, closes: true)) { url, httpClient in
            // Given: the connection dropped mid-body, and the reconnection claimed the rest of the
            // download. The continuation waits ten minutes before it starts, and the test ends it first.
            let setup = try await ReconnectionSetup(url: url)
            let fixture = await ClientFixture(url: url, setup: setup)
            let task = httpClient.execute(request: try .init(url: url), delegate: fixture.receiver)
            await #expect(throws: (any Error).self) { try await task.futureResult.get() }

            // When
            fixture.receiver.failIfNotStarted(TestFailure())

            // Then: the download is still the reconnection's to end, and ends cleanly.
            setup.reconnection.terminate { fixture.download.close() }

            var received = 0
            for try await chunk in fixture.download.stream {
                received += chunk.readableBytes
            }

            #expect(received == 10)
        }
    }

    // MARK: - ResumedResponseReceiver

    @Test(.timeLimit(.minutes(1)))
    func resumedReceiver_endsAContinuationThatWasAccepted() async throws {
        try await withHTTPClient(.resumed(length: 100, sent: 10)) { url, httpClient in
            // Given: the head was validated and the first part of the body delivered.
            let setup = try await ReconnectionSetup(url: url)
            let receiver = setup.makeResumedReceiver(url: url, completeLength: 100)
            let task = httpClient.execute(request: try .init(url: url), delegate: receiver)

            var body = setup.download.stream.makeAsyncIterator()
            let first = try await body.next()
            #expect(first?.readableBytes == 10)

            // When
            receiver.failIfNotStarted(TestFailure())

            // Then
            await #expect(throws: TestFailure.self) {
                while try await body.next() != nil {}
            }

            withExtendedLifetime(task) {}
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func resumedReceiver_leavesAContinuationTheDelegateWasToldTheEndOf() async throws {
        try await withHTTPClient(.resumed(length: 10, sent: 10)) { url, httpClient in
            // Given: `didFinishRequest` ran.
            let setup = try await ReconnectionSetup(url: url)
            let receiver = setup.makeResumedReceiver(url: url, completeLength: 10)
            let task = httpClient.execute(request: try .init(url: url), delegate: receiver)
            try await task.futureResult.get()

            // When
            receiver.failIfNotStarted(TestFailure())

            // Then
            var received = 0
            for try await chunk in setup.download.stream {
                received += chunk.readableBytes
            }

            #expect(received == 10)
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func resumedReceiver_leavesAContinuationAnotherOneTookOver() async throws {
        try await withHTTPClient(.resumed(length: 100, sent: 10, closes: true)) { url, httpClient in
            // Given: the connection dropped mid-body and the reconnection claimed the rest of the download.
            let setup = try await ReconnectionSetup(url: url)
            let receiver = setup.makeResumedReceiver(url: url, completeLength: 100)
            let task = httpClient.execute(request: try .init(url: url), delegate: receiver)
            await #expect(throws: (any Error).self) { try await task.futureResult.get() }

            // When
            receiver.failIfNotStarted(TestFailure())

            // Then: the download is still the reconnection's to end, and ends cleanly.
            setup.reconnection.terminate { setup.download.close() }

            var received = 0
            for try await chunk in setup.download.stream {
                received += chunk.readableBytes
            }

            #expect(received == 10)
        }
    }
}

// MARK: - Fixtures

private struct TestFailure: Error {}

/// The response a scripted server answers the first read with.
private struct Script {

    let bytes: String
    let closes: Bool

    static let body = "0123456789"

    /// A `200` with a strong validator, so that the download can be resumed.
    static func original(length: Int, sent: Int, closes: Bool = false) -> Script {
        Script(
            bytes: "HTTP/1.1 200 OK\r\nETag: \"v1\"\r\nContent-Length: \(length)\r\n\r\n" + body.prefix(sent),
            closes: closes
        )
    }

    /// The `206` a continuation of `original(length:...)` is answered with.
    static func resumed(length: Int, sent: Int, closes: Bool = false) -> Script {
        Script(
            bytes: "HTTP/1.1 206 Partial Content\r\nETag: \"v1\"\r\nContent-Range: bytes 0-\(length - 1)/\(length)\r\n"
                + "Content-Length: \(length)\r\n\r\n" + body.prefix(sent),
            closes: closes
        )
    }
}

/// Serves `script` to the first read of every connection, and holds the connection open unless it says
/// to close it.
private final class ScriptedHandler: ChannelInboundHandler, @unchecked Sendable {

    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let script: Script
    private var didRespond = false

    init(_ script: Script) {
        self.script = script
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !didRespond else {
            return
        }

        didRespond = true

        let channel = context.channel
        var buffer = channel.allocator.buffer(capacity: script.bytes.utf8.count)
        buffer.writeString(script.bytes)

        let closes = script.closes
        context.writeAndFlush(wrapOutboundOut(buffer)).whenComplete { _ in
            if closes {
                channel.close(promise: nil)
            }
        }
    }
}

private func withHTTPClient<Result>(
    _ script: Script,
    perform body: (_ url: String, _ httpClient: HTTPClient) async throws -> Result
) async throws -> Result {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 2)

    let server = try await ServerBootstrap(group: group)
        .childChannelInitializer { channel in
            channel.pipeline.addHandler(ScriptedHandler(script))
        }
        .bind(host: "127.0.0.1", port: 0)
        .get()

    let httpClient = HTTPClient(eventLoopGroupProvider: .shared(group))
    let url = "http://127.0.0.1:\(server.localAddress!.port!)"

    do {
        let result = try await body(url, httpClient)
        try await httpClient.shutdown()
        try? await server.close()
        try await group.shutdownGracefully()
        return result
    } catch {
        try? await httpClient.shutdown()
        try? await server.close()
        try? await group.shutdownGracefully()
        throw error
    }
}

/// The streams a `ClientResponseReceiver` writes to, built the way `Internals.Client.execute` builds them.
private struct ClientFixture {

    let receiver: Internals.ClientResponseReceiver
    let upload: Internals.AsyncStream<Int>
    let head: Internals.AsyncStream<Internals.ResponseHead>
    let download: Internals.DownloadBuffer

    init(url: String, setup: ReconnectionSetup? = nil) async {
        upload = Internals.AsyncStream<Int>()
        head = Internals.AsyncStream<Internals.ResponseHead>()
        if let setup {
            download = setup.download
        } else {
            download = await Internals.DownloadBuffer(readingMode: .length(10), flowControl: .init(), observer: nil)
        }

        receiver = Internals.ClientResponseReceiver(
            url: url,
            upload: upload,
            head: head,
            download: download,
            cache: nil,
            decompressionDispatch: .skip,
            logger: nil,
            transferControl: setup?.transferControl,
            reconnection: setup?.reconnection
        )
    }
}

/// A download that reconnects, with a delay long enough that no continuation starts while a test runs.
private struct ReconnectionSetup {

    let download: Internals.DownloadBuffer
    let transferControl: Internals.TransferControl
    let reconnection: Internals.NIODownloadReconnection

    init(url: String) async throws {
        let flowControl = Internals.FlowControlWindow()
        let policy = Internals.DownloadResumptionPolicy(maximumAttemptsWithoutProgress: 3, delay: 600_000_000_000)

        download = await Internals.DownloadBuffer(readingMode: .length(10), flowControl: flowControl)
        transferControl = Internals.TransferControl(resumption: policy)

        let session = Internals.Session(
            provider: .identified("com.requestdl.tests.fail-if-not-started", numberOfThreads: 1),
            configuration: .init()
        )

        reconnection = Internals.NIODownloadReconnection(
            client: try await session.client(),
            request: try HTTPClient.Request(url: url),
            url: url,
            download: download,
            flowControl: flowControl,
            transferControl: transferControl,
            policy: policy,
            logger: nil
        )
    }

    /// The receiver of a continuation that resumes at the start of a representation `completeLength` long.
    func makeResumedReceiver(url: String, completeLength: Int64) -> Internals.ResumedResponseReceiver {
        // What the original exchange's head would have told the reconnection: a strong validator.
        reconnection.didReceiveOriginalHead(
            Internals.ResponseHead(
                url: url,
                status: .init(code: 200, reason: "OK"),
                version: .init(minor: 1, major: 1),
                headers: [.init(name: "ETag", value: "\"v1\"")],
                isKeepAlive: true
            )
        )

        return Internals.ResumedResponseReceiver(
            url: url,
            download: download,
            attempt: .init(
                number: 1,
                offset: 0,
                plan: .init(validator: .entityTag("\"v1\""), completeLength: completeLength),
                headers: []
            ),
            reconnection: reconnection
        )
    }
}

#endif
