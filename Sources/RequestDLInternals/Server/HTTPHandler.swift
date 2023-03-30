/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIO
import NIOHTTP1

final class HTTPHandler<Response: Codable> where Response: Equatable {

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var result: HTTPResult<Response>

    private var resultData: Data{
        (try? result.encode()) ?? Data()
    }

    init(_ response: Response) {
        self.result = .init(
            receivedBytes: .zero,
            response: response
        )
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
            response.headers.add(name: "content-length", value: "\(resultData.count)")
            result.receivedBytes = .zero

            context.write(wrapOutboundOut(.head(response)), promise: nil)
        case .body(let bytes):
            result.receivedBytes += bytes.readableBytes
        case .end:
            var headers = HTTPHeaders()
            let buffer = ByteBuffer(bytes: resultData)
            headers.add(name: "content-length", value: "\(resultData.count)")

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
