//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import NIO
import NIOConcurrencyHelpers
import NIOHTTP1
import NIOHTTP2
import NIOSSL

/// A minimal TLS server that only negotiates `h2` through ALPN.
///
/// `LocalServer` speaks HTTP/1.1 only, so it can't prove anything about HTTP/2. This server
/// advertises *only* `h2`: a client that can't (or won't) speak HTTP/2 fails the handshake
/// instead of silently falling back to HTTP/1.1, so a request that completes against it is
/// itself proof of the negotiated protocol. It records what each stream actually carried on the
/// wire and answers every request with an empty `200`.
final class HTTP2LocalServer: @unchecked Sendable {

    struct Request: Sendable {
        let method: String
        let path: String
        let headers: HTTPHeaders
        let body: ByteBuffer
    }

    // MARK: - Private properties

    private let group: MultiThreadedEventLoopGroup
    private let channel: Channel
    private let lock = NIOLock()

    // MARK: - Unsafe properties

    private var _requests: [Request] = []

    // MARK: - Inits

    private init(group: MultiThreadedEventLoopGroup, channel: Channel, requests: Recorder) {
        self.group = group
        self.channel = channel
        requests.server = self
    }

    // MARK: - Internal static methods

    static func start() async throws -> HTTP2LocalServer {
        var tlsConfiguration = try LocalServer.TLSOption.none.build()
        tlsConfiguration.applicationProtocols = ["h2"]
        let sslContext = try NIOSSLContext(configuration: tlsConfiguration)

        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let recorder = Recorder()

        do {
            let channel = try await ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    initialize(channel, sslContext: sslContext, recorder: recorder)
                }
                .bind(host: "localhost", port: .zero)
                .get()

            return HTTP2LocalServer(group: group, channel: channel, requests: recorder)
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
    }

    // MARK: - Private static methods

    private static func initialize(
        _ channel: Channel,
        sslContext: NIOSSLContext,
        recorder: Recorder
    ) -> EventLoopFuture<Void> {
        // Runs on the channel's event loop, so the synchronous pipeline operations apply: they
        // take the (deliberately non-`Sendable`) handlers directly instead of sending them
        // across an isolation boundary.
        channel.eventLoop.makeCompletedFuture {
            let operations = channel.pipeline.syncOperations

            try operations.addHandler(NIOSSLServerHandler(context: sslContext))
            _ = try operations.configureHTTP2Pipeline(
                mode: .server,
                connectionConfiguration: .init(),
                streamConfiguration: .init(),
                inboundStreamInitializer: { stream in
                    stream.eventLoop.makeCompletedFuture {
                        try stream.pipeline.syncOperations.addHandlers([
                            HTTP2FramePayloadToHTTP1ServerCodec(),
                            StreamHandler(recorder),
                        ])
                    }
                }
            )
        }
    }

    // MARK: - Internal properties

    var port: Int {
        channel.localAddress?.port ?? .zero
    }

    var baseURL: String {
        "localhost:\(port)"
    }

    var requests: [Request] {
        lock.withLock { _requests }
    }

    // MARK: - Internal methods

    func stop() async throws {
        try await channel.close()
        try await group.shutdownGracefully()
    }

    // MARK: - Private methods

    fileprivate func record(_ request: Request) {
        lock.withLock { _requests.append(request) }
    }
}

extension HTTP2LocalServer {

    /// Breaks the init-order cycle between the server (which needs the bound channel) and the
    /// stream handlers (which need somewhere to report to before the channel exists).
    fileprivate final class Recorder: @unchecked Sendable {

        private let lock = NIOLock()
        private var _server: HTTP2LocalServer?

        var server: HTTP2LocalServer? {
            get { lock.withLock { _server } }
            set { lock.withLock { _server = newValue } }
        }

        func record(_ request: Request) {
            server?.record(request)
        }
    }

    fileprivate final class StreamHandler: ChannelInboundHandler, @unchecked Sendable {

        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart

        private let recorder: Recorder
        private var head: HTTPRequestHead?
        private var body = ByteBuffer()

        init(_ recorder: Recorder) {
            self.recorder = recorder
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            switch unwrapInboundIn(data) {
            case .head(let head):
                self.head = head
            case .body(var chunk):
                body.writeBuffer(&chunk)
            case .end:
                if let head {
                    recorder.record(
                        Request(method: head.method.rawValue, path: head.uri, headers: head.headers, body: body)
                    )
                }

                var headers = HTTPHeaders()
                headers.add(name: "content-length", value: "0")

                context.write(
                    wrapOutboundOut(.head(HTTPResponseHead(version: .http2, status: .ok, headers: headers))),
                    promise: nil
                )
                context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            }
        }
    }
}

#endif
