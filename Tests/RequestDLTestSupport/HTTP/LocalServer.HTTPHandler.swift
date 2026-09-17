//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import NIO
import NIOConcurrencyHelpers
import NIOHTTP1
import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension LocalServer {

    /// `@unchecked` rather than provably `Sendable`: NIO guarantees every `ChannelHandler`
    /// callback for one channel runs on that channel's own `EventLoop`, one at a time, so the
    /// mutable state below is never actually touched concurrently; the compiler just can't see
    /// that guarantee through the `EventLoopFuture` callbacks in `channelReadComplete`, which is
    /// what actually needs this.
    final class HTTPHandler: ChannelInboundHandler, @unchecked Sendable {

        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart

        // MARK: - Private properties

        private let responseQueue: ResponseQueue
        private var isNewConnection = true
        private var receivedAllParts = false

        private var _configuration: ResponseConfiguration?

        private var _uri: String?
        private var _method: NIOHTTP1.HTTPMethod?
        private var _version: NIOHTTP1.HTTPVersion?
        private var _isKeepAlive: Bool?
        private var _incomeHeaders: Internals.HTTPHeaders?
        private var _incomeBuffer: ByteBuffer?

        // MARK: - Inits

        init(_ responseQueue: ResponseQueue) {
            self.responseQueue = responseQueue
        }

        // MARK: - Internal methods

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            if isNewConnection {
                cleanup()
                isNewConnection = false
            }

            let request = unwrapInboundIn(data)

            switch request {
            case .head(let incomeHeaders):
                _configuration = responseQueue.popLast(at: incomeHeaders.uri)
                var headers = _incomeHeaders ?? .init()
                for (name, value) in incomeHeaders.headers {
                    headers.add(name: name, value: value)
                }
                _incomeHeaders = headers

                _method = incomeHeaders.method
                _uri = incomeHeaders.uri
                _version = incomeHeaders.version
                _isKeepAlive = incomeHeaders.isKeepAlive
            case .body(let incomeBuffer):
                var incomeBuffer = incomeBuffer.slice()
                var buffer = _incomeBuffer ?? .init()
                buffer.writeBuffer(&incomeBuffer)
                _incomeBuffer = buffer
            case .end(let incomeHeaders):
                receivedAllParts = true

                guard let incomeHeaders else {
                    break
                }

                var headers = _incomeHeaders ?? .init()
                for (name, value) in incomeHeaders {
                    headers.add(name: name, value: value)
                }
            }
        }

        func channelReadComplete(context: ChannelHandlerContext) {
            guard receivedAllParts else {
                return
            }

            defer { cleanup() }

            let response = LocalServer.makeResponseBody(
                configuration: _configuration,
                receivedBytes: _incomeBuffer?.readableBytes ?? .zero,
                incomeHeaders: _incomeHeaders
            )

            let headers = LocalServer.headers(
                _configuration?.headers ?? .init(),
                replacingContentLengthWith: response?.count ?? .zero
            )

            let head = HTTPResponseHead(
                version: _version ?? .http1_1,
                status: (_configuration?.status ?? .ok).build(),
                headers: headers.build()
            )

            // `channel`, not `context` itself, is what's safe to hold onto across these
            // `EventLoopFuture` callbacks: `Channel` is `Sendable`, `ChannelHandlerContext` isn't.
            // Written as raw `HTTPServerResponsePart` values, not `self.wrapOutboundOut(...)`'s
            // `NIOAny`: `Channel.writeAndFlush` has a generic `Sendable`-constrained overload for
            // exactly this (`HTTPServerResponsePart` is `Sendable`: `HTTPResponseHead` and `IOData`
            // both are), where the `NIOAny`-typed overload is deprecated.
            //
            // Safe to skip the pipeline position `wrapOutboundOut`/`context` would preserve, since
            // this handler is the only one ever installed on this channel's pipeline (see
            // `LocalServer`'s `childChannelInitializer`).
            let channel = context.channel

            channel.writeAndFlush(HTTPServerResponsePart.head(head))
                .flatMapWithEventLoop { _, eventLoop in
                    guard let data = response, self._method != .HEAD else {
                        return eventLoop.makeSucceededVoidFuture()
                    }

                    let ioData = IOData.byteBuffer(.init(data: data))
                    return channel.writeAndFlush(HTTPServerResponsePart.body(ioData))
                }.flatMap {
                    channel.writeAndFlush(HTTPServerResponsePart.end(nil))
                }.whenComplete { _ in
                    self._configuration = nil
                    self.isNewConnection = true
                }
        }

        // MARK: - Private methods

        private func cleanup() {
            _method = nil
            _uri = nil
            _version = nil
            _isKeepAlive = nil
            _incomeHeaders = nil
            _incomeBuffer = nil
            receivedAllParts = false
        }
    }
}

#endif
