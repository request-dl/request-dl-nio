//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import NIO
import NIOConcurrencyHelpers
import NIOHTTP1

/// A plain-HTTP server on a port the system picks, that answers each request with what a closure
/// decides and remembers every request it got, headers included.
///
/// For the tests that have to prove what reached the wire: which method, which path and which
/// headers a redirected request was sent with. Two instances are two origins (two ports), and
/// nothing about them is shared, so a suite does not compete with another one for a fixed port.
///
/// Every connection is closed after its response, so no request depends on a connection an earlier
/// one left behind.
final class ScriptedServer: Sendable {

    // MARK: - Inner types

    /// A request as the server received it.
    struct Received: Sendable {

        let method: String
        let uri: String
        let headers: [(name: String, value: String)]

        /// The value of the first header named `name`, whatever the case.
        func header(_ name: String) -> String? {
            headers.first { $0.name.lowercased() == name.lowercased() }?.value
        }
    }

    /// What the server answers a request with.
    struct Reply: Sendable {

        var status: Int
        var headers: [(name: String, value: String)]
        var body: String

        static func redirect(_ status: Int = 302, to location: String) -> Self {
            Reply(status: status, headers: [("Location", location)], body: "")
        }

        static func ok(_ body: String = "reached") -> Self {
            Reply(status: 200, headers: [], body: body)
        }
    }

    // MARK: - Private properties

    private let group: MultiThreadedEventLoopGroup
    private let channel: Channel
    private let log: NIOLockedValueBox<[Received]>

    // MARK: - Internal properties

    /// The requests received so far, in the order they arrived.
    var requests: [Received] {
        log.withLockedValue { $0 }
    }

    let port: Int

    /// `http://127.0.0.1:<port>`, the origin of this server.
    var origin: String {
        "http://127.0.0.1:\(port)"
    }

    // MARK: - Inits

    /// - Parameter respond: Decides the answer to a request. Runs on the server's event loop: it
    /// must not block.
    init(respond: @escaping @Sendable (Received) -> Reply) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let log = NIOLockedValueBox<[Received]>([])

        let channel = try await ServerBootstrap(group: group)
            .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMapThrowing {
                    try channel.pipeline.syncOperations.addHandler(Handler(log: log, respond: respond))
                }
            }
            .bind(host: "127.0.0.1", port: 0)
            .get()

        self.group = group
        self.channel = channel
        self.log = log
        self.port = channel.localAddress?.port ?? 0
    }

    // MARK: - Internal methods

    func shutdown() async {
        try? await channel.close().get()
        try? await group.shutdownGracefully()
    }

    // MARK: - Inner types (handler)

    private final class Handler: ChannelInboundHandler, @unchecked Sendable {

        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart

        private let log: NIOLockedValueBox<[Received]>
        private let respond: @Sendable (Received) -> Reply
        private var head: HTTPRequestHead?

        init(log: NIOLockedValueBox<[Received]>, respond: @escaping @Sendable (Received) -> Reply) {
            self.log = log
            self.respond = respond
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            switch unwrapInboundIn(data) {
            case .head(let head):
                self.head = head

            case .body:
                break

            case .end:
                guard let head else {
                    return
                }

                self.head = nil

                let received = Received(
                    method: head.method.rawValue,
                    uri: head.uri,
                    headers: head.headers.map { (name: $0.name, value: $0.value) }
                )

                log.withLockedValue { $0.append(received) }

                let reply = respond(received)

                var headers = HTTPHeaders()
                for (name, value) in reply.headers {
                    headers.add(name: name, value: value)
                }
                headers.replaceOrAdd(name: "Content-Length", value: String(reply.body.utf8.count))
                headers.replaceOrAdd(name: "Connection", value: "close")

                let responseHead = HTTPResponseHead(
                    version: .http1_1,
                    status: .init(statusCode: reply.status),
                    headers: headers
                )

                context.write(wrapOutboundOut(.head(responseHead)), promise: nil)

                // A response to `HEAD` has the headers of the body it would have had, not the body.
                if head.method != .HEAD {
                    var buffer = context.channel.allocator.buffer(capacity: reply.body.utf8.count)
                    buffer.writeString(reply.body)
                    context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                }

                context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
                    context.close(promise: nil)
                }
            }
        }
    }
}

#endif
