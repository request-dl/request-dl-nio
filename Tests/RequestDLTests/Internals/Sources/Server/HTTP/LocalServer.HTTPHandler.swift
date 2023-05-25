/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIO
import NIOHTTP1

extension LocalServer {

    final class HTTPHandler: ChannelInboundHandler {

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
        private var _incomeHeaders: NIOHTTP1.HTTPHeaders?
        private var _incomeBuffer: ByteBuffer?

        // MARK: - Inits

        init(_ responseQueue: ResponseQueue) {
            self.responseQueue = responseQueue
        }

        // MARK: - Internal methods

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            if isNewConnection {
                _configuration = responseQueue.popLast()
                cleanup()
                isNewConnection = false
            }

            let request = unwrapInboundIn(data)

            switch request {
            case .head(let incomeHeaders):
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

            var headers = _configuration?.headers ?? .init()
            let response = responseData()

            headers.replaceOrAdd(
                name: "Content-Length",
                value: String(response?.count ?? .zero)
            )

            let head = HTTPResponseHead(
                version: _version ?? .http1_1,
                status: .ok,
                headers: headers
            )

            context.writeAndFlush(self.wrapOutboundOut(.head(head)))
                .flatMapWithEventLoop { _, eventLoop in
                    guard let data = response, self._method != .HEAD else {
                        return eventLoop.makeSucceededVoidFuture()
                    }

                    let ioData = IOData.byteBuffer(.init(data: data))
                    return context.writeAndFlush(self.wrapOutboundOut(.body(ioData)))
                }.flatMap {
                    context.writeAndFlush(self.wrapOutboundOut(.end(nil)))
                }.whenComplete { _ in
                    self._configuration = nil
                    self.isNewConnection = true
                }
        }

        // MARK: - Private methods

        private func responseData() -> Data? {
            var receivedBytes = Int.zero

            if let _incomeBuffer {
                receivedBytes += _incomeBuffer.readableBytes
            }

            let response = _configuration.map {
                try? JSONSerialization.jsonObject(
                    with: $0.data,
                    options: [.fragmentsAllowed]
                )
            }

            var jsonObject = [String: Any]()

            jsonObject["receivedBytes"] = receivedBytes

            if let response {
                jsonObject["response"] = response
            }

            return try? JSONSerialization.data(
                withJSONObject: jsonObject,
                options: [.sortedKeys]
            )
        }

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
