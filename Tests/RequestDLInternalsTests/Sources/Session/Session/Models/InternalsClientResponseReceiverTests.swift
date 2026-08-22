//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import NIOPosix
import Testing

@testable import RequestDLInternals

/// Executes a bare GET against `urlString` through `session`, mirroring what
/// `RequestDL`'s `RawTask` does once it has resolved a `RequestConfiguration` into a plain
/// `HTTPClient.Request` -- this file has no access to `RequestConfiguration` itself, since that
/// type lives in `RequestDL`, which depends on this module rather than the other way around.
private func execute(session: Internals.Session, urlString: String) async throws -> Internals.AsyncResponse {
    let client = try await session.client()
    let request = try HTTPClient.Request(url: urlString)

    let task = try await session.execute(
        client: client,
        request: request,
        url: urlString,
        readingMode: .length(1_024),
        uploadingBytes: .zero,
        cache: nil,
        logger: nil
    )

    return task.response
}

struct InternalsClientResponseReceiverTests {

    @Test
    func connectionErrorBeforeAnyDataIsSentReachesTheHeadStream() async throws {
        // Given
        // Nothing listens on this port, so the connect attempt itself fails — never
        // establishing a connection means `didSendRequestPart`/`didSendRequest` never run, and
        // `ClientResponseReceiver` is still in its initial `.idle` state when `didReceiveError`
        // fires. A short connect timeout keeps this from riding out the client's full default.
        var configuration = Internals.Session.Configuration()
        configuration.timeout.connect = 200_000_000

        let session = Internals.Session(
            provider: .identified("com.requestdl.tests.connection-refused", numberOfThreads: 1),
            configuration: configuration
        )

        // When
        let response = try await execute(session: session, urlString: "http://127.0.0.1:1")

        // Then
        await #expect(throws: (any Error).self) {
            for try await _ in response {}
        }
    }

    @Test
    func connectionDroppedAfterUploadReachesTheUploadStream() async throws {
        try await withScriptedServer(.closeAfterFirstRead) { port in
            // Given
            // The server accepts the connection and reads the request, so the client has
            // already gone through `didSendRequestPart`/`didSendRequest` (state `.uploading`)
            // before the abrupt close surfaces as an error — no response head is ever sent.
            let session = Internals.Session(
                provider: .identified("com.requestdl.tests.drop-after-upload", numberOfThreads: 1),
                configuration: .init()
            )

            // When
            let response = try await execute(session: session, urlString: "http://127.0.0.1:\(port)")

            // Then
            await #expect(throws: (any Error).self) {
                for try await _ in response {}
            }
        }
    }

    @Test
    func connectionDroppedAfterHeadOnlyReachesTheHeadStream() async throws {
        try await withScriptedServer(.respondHeadThenClose) { port in
            // Given
            // A complete, valid response head promises more body than ever arrives, so
            // `didReceiveHead` runs (state `.head`) before the connection drops mid-body.
            let session = Internals.Session(
                provider: .identified("com.requestdl.tests.drop-after-head", numberOfThreads: 1),
                configuration: .init()
            )

            // When
            let response = try await execute(session: session, urlString: "http://127.0.0.1:\(port)")

            // Then
            // The truncated body surfaces while draining `step.bytes`, not at the top-level
            // `response` sequence itself — the head alone arrives intact.
            await #expect(throws: (any Error).self) {
                for try await step in response {
                    guard case .download(let download) = step else { continue }
                    for try await _ in download.bytes {}
                }
            }
        }
    }

    @Test
    func connectionDroppedMidBodyReachesTheDownloadStream() async throws {
        try await withScriptedServer(.respondPartialBodyThenClose) { port in
            // Given
            // The response head plus a first body chunk gets `didReceiveBodyPart` to run (state
            // `.downloading`) before the rest of the promised body never shows up.
            let session = Internals.Session(
                provider: .identified("com.requestdl.tests.drop-mid-body", numberOfThreads: 1),
                configuration: .init()
            )

            // When
            let response = try await execute(session: session, urlString: "http://127.0.0.1:\(port)")

            // Then
            await #expect(throws: (any Error).self) {
                for try await step in response {
                    guard case .download(let download) = step else { continue }
                    for try await _ in download.bytes {}
                }
            }
        }
    }
}

/// A bare, non-HTTP-aware TCP server that reacts to the first bytes it reads according to
/// `script`, used to force `Internals.ClientResponseReceiver` into a specific state right before
/// the connection dies — something `LocalServer` cannot do, since it always waits for a
/// complete request and always answers with a complete, valid response.
private enum ScriptedServerBehavior {

    /// Reads the request, then closes without ever responding — lands the receiver in
    /// `.uploading`.
    case closeAfterFirstRead

    /// Sends a complete head promising more body than follows, then closes — lands the
    /// receiver in `.head`.
    case respondHeadThenClose

    /// Sends a complete head plus a first body chunk, then closes before the rest of the
    /// promised body arrives — lands the receiver in `.downloading`.
    case respondPartialBodyThenClose
}

private func withScriptedServer<Result>(
    _ behavior: ScriptedServerBehavior,
    perform body: (Int) async throws -> Result
) async throws -> Result {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    let bootstrap = ServerBootstrap(group: group)
        .childChannelInitializer { channel in
            channel.pipeline.addHandler(ScriptedServerHandler(behavior))
        }

    let serverChannel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
    let port = serverChannel.localAddress!.port!

    do {
        let result = try await body(port)
        try? await serverChannel.close()
        try await group.shutdownGracefully()
        return result
    } catch {
        try? await serverChannel.close()
        try await group.shutdownGracefully()
        throw error
    }
}

private final class ScriptedServerHandler: ChannelInboundHandler, @unchecked Sendable {

    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private let behavior: ScriptedServerBehavior

    init(_ behavior: ScriptedServerBehavior) {
        self.behavior = behavior
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch behavior {
        case .closeAfterFirstRead:
            context.close(promise: nil)

        case .respondHeadThenClose:
            write(
                "HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n",
                context: context,
                thenClose: true
            )

        case .respondPartialBodyThenClose:
            write(
                "HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n0123456789",
                context: context,
                thenClose: true
            )
        }
    }

    private func write(_ string: String, context: ChannelHandlerContext, thenClose: Bool) {
        let channel = context.channel
        var buffer = channel.allocator.buffer(capacity: string.utf8.count)
        buffer.writeString(string)

        context.writeAndFlush(wrapOutboundOut(buffer)).whenComplete { _ in
            if thenClose {
                channel.close(promise: nil)
            }
        }
    }
}
