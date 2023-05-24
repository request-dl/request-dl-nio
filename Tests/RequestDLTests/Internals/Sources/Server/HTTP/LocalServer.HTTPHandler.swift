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

        private let bag: RequestBag
        private var receivedAllParts = false

        private var _configuration: ResponseConfiguration?

        private var _uri: String?
        private var _method: NIOHTTP1.HTTPMethod?
        private var _version: NIOHTTP1.HTTPVersion?
        private var _isKeepAlive: Bool?
        private var _incomeHeaders: NIOHTTP1.HTTPHeaders?
        private var _incomeBuffer: ByteBuffer?

        init(_ bag: RequestBag) {
            self.bag = bag
        }

        func channelActive(context: ChannelHandlerContext) {
            _configuration = bag.latestConfiguration()
            receivedAllParts = false
            cleanup()
        }

        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
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

            context.write(
                wrapOutboundOut(.head(head)),
                promise: nil
            )

            if let data = response, _method != .HEAD {
                let ioData = IOData.byteBuffer(.init(data: data))
                context.write(
                    wrapOutboundOut(.body(ioData)),
                    promise: nil
                )
            }

            context.writeAndFlush(
                wrapOutboundOut(.end(nil)),
                promise: nil
            )

            context.close(promise: nil)
        }

        func channelInactive(context: ChannelHandlerContext) {
            _configuration = nil
            bag.consume()
        }

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
