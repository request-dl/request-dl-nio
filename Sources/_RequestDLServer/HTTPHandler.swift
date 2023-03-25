/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIO
import NIOHTTP1

final class HTTPHandler<Response: Codable> {

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var result: HTTPResult<Response>

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
            let response = HTTPResponseHead(
                version: head.version,
                status: HTTPResponseStatus.ok
            )

            context.write(wrapOutboundOut(.head(response)), promise: nil)
        case .body(let bytes):
            result.receivedBytes += bytes.readableBytes
        case .end:
            let data = (try? result.encode()) ?? Data()
            let buffer = ByteBuffer(bytes: data)

            var headers = HTTPHeaders()
            headers.add(name: "content-length", value: "\(data.count)")

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
