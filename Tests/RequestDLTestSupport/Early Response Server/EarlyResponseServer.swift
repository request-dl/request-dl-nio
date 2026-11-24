//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import NIO
import NIOHTTP1

/// A plain HTTP/1.1 server that answers as soon as the request *head* arrives, without ever
/// reading the body, and (unless told to keep the connection) closes right after.
///
/// This is the server of the early-response scenario: a client that is still streaming a large
/// body gets its answer (`413`, `408`, `401`, even a `200`) before it is done sending, and the
/// connection goes away with request data left unread, which the kernel turns into a reset. What
/// the client must do then is hand the answer over, not hang and not report a closed connection.
package final class EarlyResponseServer: @unchecked Sendable {

    // MARK: - Package properties

    package let port: Int

    // MARK: - Private properties

    private let group: MultiThreadedEventLoopGroup
    private let listener: any Channel

    // MARK: - Inits

    package init(status: Int, keepAlive: Bool = false) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        do {
            let listener = try await ServerBootstrap(group: group)
                .childChannelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.configureHTTPServerPipeline()
                        try channel.pipeline.syncOperations.addHandler(
                            AnswerOnHead(status: status, keepAlive: keepAlive)
                        )
                    }
                }
                .bind(host: "127.0.0.1", port: 0)
                .get()

            self.group = group
            self.listener = listener
            self.port = listener.localAddress?.port ?? 0
        } catch {
            try? await group.shutdownGracefully()
            throw error
        }
    }

    // MARK: - Package methods

    package func stop() async {
        try? await listener.close()
        try? await group.shutdownGracefully()
    }

    // MARK: - Private types

    private final class AnswerOnHead: ChannelInboundHandler {
        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart

        private let status: Int
        private let keepAlive: Bool
        private var answered = false

        init(status: Int, keepAlive: Bool) {
            self.status = status
            self.keepAlive = keepAlive
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            guard case .head = unwrapInboundIn(data), !answered else {
                return
            }

            answered = true

            // 1xx, 204 and 304 carry no body by definition, and no `Content-Length` either.
            let hasBody = !(status < 200 || status == 204 || status == 304)

            var headers = HTTPHeaders()
            if hasBody {
                headers.add(name: "Content-Length", value: "2")
            }

            if !keepAlive {
                headers.add(name: "Connection", value: "close")
            }

            let head = HTTPResponseHead(
                version: .http1_1,
                status: HTTPResponseStatus(statusCode: status),
                headers: headers
            )

            context.write(wrapOutboundOut(.head(head)), promise: nil)

            if hasBody {
                context.write(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(string: "{}")))), promise: nil)
            }

            let keepAlive = keepAlive
            context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
                if !keepAlive {
                    context.close(promise: nil)
                }
            }
        }

        func errorCaught(context: ChannelHandlerContext, error: Error) {
            context.close(promise: nil)
        }
    }
}

#endif
