/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIO
import NIOHTTP1

final class HTTPHandler<Response: Codable> where Response: Equatable {

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let noCache: Bool
    private let maxAge: Bool
    private var result: HTTPResult<Response>

    private var resultData: Data {
        (try? result.encode()) ?? Data()
    }

    init(
        response: Response,
        noCache: Bool,
        maxAge: Bool
    ) {
        self.noCache = noCache
        self.maxAge = maxAge
        self.result = .init(
            receivedBytes: .zero,
            response: response
        )
    }

    func addCacheHeaders(in headers: inout HTTPHeaders) {
        headers.add(name: "ETag", value: resultData.base64EncodedString())

        if noCache {
            headers.add(name: "Cache-Control", value: "no-cache")
        } else {
            let now = Date()
            let maxAge = 5
            let date = now.addingTimeInterval(TimeInterval(maxAge))

            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            dateFormatter.timeZone = TimeZone(identifier: "GMT")

            if self.maxAge {
                headers.add(name: "Cache-Control", value: "public, max-age=\(maxAge)")
            } else {
                headers.add(name: "Cache-Control", value: "public")
                headers.add(name: "Expires", value: dateFormatter.string(from: date))
            }
        }
    }
}

extension HTTPHandler: ChannelInboundHandler {

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = unwrapInboundIn(data)

        switch request {
        case .head(let head):
            var response = HTTPResponseHead(
                version: head.version,
                status: HTTPResponseStatus.ok
            )

            let value = head.headers.first(name: "content-length")
                .flatMap(Int.init) ?? .zero

            result.receivedBytes = value
            response.headers.add(name: "content-length", value: String(resultData.count))
            addCacheHeaders(in: &response.headers)
            result.receivedBytes = .zero

            context.write(wrapOutboundOut(.head(response)), promise: nil)
        case .body(let bytes):
            result.receivedBytes += bytes.readableBytes
        case .end:
            var headers = HTTPHeaders()
            let buffer = ByteBuffer(bytes: resultData)

            headers.add(name: "content-length", value: String(resultData.count))
            addCacheHeaders(in: &headers)

            context.writeAndFlush(wrapOutboundOut(.body(.byteBuffer(buffer))))
                .flatMap {
                    context.writeAndFlush(self.wrapOutboundOut(.end(headers)))
                }
                .whenComplete { _ in
                    context.close(promise: nil)
                }
        }
    }
}
