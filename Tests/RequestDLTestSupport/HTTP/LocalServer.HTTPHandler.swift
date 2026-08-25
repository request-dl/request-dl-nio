//
// See LICENSE for this package's licensing information.
//

import NIO
import NIOConcurrencyHelpers
import NIOHTTP1
import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import class Foundation.JSONEncoder
import class Foundation.JSONDecoder
#endif

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

            var headers = _configuration?.headers ?? .init()
            let response = responseData()

            headers.replaceOrAdd(
                name: "Content-Length",
                value: String(response?.count ?? .zero)
            )

            let head = HTTPResponseHead(
                version: _version ?? .http1_1,
                status: _configuration?.status ?? .ok,
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

            // `JSONValue` stands in for `JSONSerialization`'s `Any`, which is not part of
            // `FoundationEssentials`.
            let response = _configuration.flatMap {
                try? JSONDecoder().decode(Internals.JSONValue.self, from: $0.data)
            }

            var jsonObject: [String: Internals.JSONValue] = [
                "receivedBytes": .integer(Int64(receivedBytes))
            ]

            if let response {
                jsonObject["response"] = response
            }

            // Lets a test prove what the client actually sent, not just what the server chose to
            // send back -- e.g. confirming a cookie set by an earlier response was (or, under
            // `.urlSession`'s no-jar normalization, was *not*) resent automatically.
            if let cookie = _incomeHeaders?.first(name: "Cookie") {
                jsonObject["receivedCookieHeader"] = .string(cookie)
            }

            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try? encoder.encode(jsonObject)
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
