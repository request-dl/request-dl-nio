//
// See LICENSE for this package's licensing information.
//

import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix

/// The server the benchmark talks to, in a process of its own so that what is measured is the
/// client and not a server sharing its CPU.
///
/// - `GET /download?bytes=N`: answers with `N` zero bytes, written in chunks of 64 KiB.
/// - `POST /upload`: reads the whole body and answers with how many bytes it was.
/// - `GET /small`: answers with a few bytes.

private let chunkSize = 64 * 1_024

private final class Handler: ChannelInboundHandler, @unchecked Sendable {

    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let chunk: ByteBuffer
    private var uri = ""
    private var received = 0
    private var remaining = 0
    private var isStreaming = false

    init(chunk: ByteBuffer) {
        self.chunk = chunk
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        switch unwrapInboundIn(data) {
        case .head(let head):
            uri = head.uri
            received = 0

        case .body(let buffer):
            received += buffer.readableBytes

        case .end:
            respond(context: context)
        }
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if isStreaming, context.channel.isWritable {
            writeChunks(context: context)
        }

        context.fireChannelWritabilityChanged()
    }

    private func respond(context: ChannelHandlerContext) {
        if uri.hasPrefix("/download") {
            remaining = Self.bytes(in: uri)
            isStreaming = true

            var headers = HTTPHeaders()
            headers.add(name: "Content-Length", value: String(remaining))
            context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: .ok, headers: headers))), promise: nil)
            writeChunks(context: context)
            return
        }

        let body = uri.hasPrefix("/upload") ? "received=\(received)" : "ok"
        var headers = HTTPHeaders()
        headers.add(name: "Content-Length", value: String(body.utf8.count))
        context.write(wrapOutboundOut(.head(HTTPResponseHead(version: .http1_1, status: .ok, headers: headers))), promise: nil)
        context.write(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(string: body)))), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
    }

    private func writeChunks(context: ChannelHandlerContext) {
        while remaining > 0, context.channel.isWritable {
            let count = min(remaining, chunkSize)
            remaining -= count

            var buffer = chunk
            buffer.moveWriterIndex(to: buffer.readerIndex + count)
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        }

        if remaining == 0 {
            isStreaming = false
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        } else {
            context.flush()
        }
    }

    private static func bytes(in uri: String) -> Int {
        guard let value = URLComponents(string: uri)?.queryItems?.first(where: { $0.name == "bytes" })?.value else {
            return 0
        }

        return Int(value) ?? 0
    }
}

let port = Int(CommandLine.arguments.dropFirst().first ?? "18080") ?? 18080
let group = MultiThreadedEventLoopGroup(numberOfThreads: max(2, System.coreCount / 2))
let chunk = ByteBuffer(repeating: 0, count: chunkSize)

let bootstrap = ServerBootstrap(group: group)
    .serverChannelOption(.backlog, value: 256)
    .serverChannelOption(.socketOption(.so_reuseaddr), value: 1)
    .childChannelInitializer { channel in
        channel.pipeline.configureHTTPServerPipeline().flatMap {
            channel.pipeline.addHandler(Handler(chunk: chunk))
        }
    }
    .childChannelOption(.socketOption(.tcp_nodelay), value: 1)

let channel = try bootstrap.bind(host: "127.0.0.1", port: port).wait()
print("listening on 127.0.0.1:\(port)")
fflush(stdout)

try channel.closeFuture.wait()
