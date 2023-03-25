//
//  File.swift
//  
//
//  Created by Brenno on 25/03/23.
//

import Foundation
import NIO
import NIOSSL
import NIOHTTP1

/// https://rderik.com/blog/understanding-swiftnio-by-building-a-text-modifying-server/
public struct Server {

    let host: String
    let port: UInt
    let tlsConfiguration: TLSConfiguration
    let output: Data

    public init(
        host: String,
        port: UInt,
        configuration: TLSConfiguration,
        output: Data
    ) {
        self.host = host
        self.port = port
        self.tlsConfiguration = configuration
        self.output = output
    }
}

extension Server {

    public func run(_ closure: () async throws -> Void) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
        
        do {
            let bootstrap = ServerBootstrap(group: group)
                .childChannelInitializer { channel in
                    // ③ add handlers to the pipeline
                    channel.pipeline
                        .addHandler(NIOSSLServerHandler(context: sslContext))
                        .flatMap {
                            channel.pipeline.configureHTTPServerPipeline()
                        }
                        .flatMap {
                            channel.pipeline.addHandler(HTTPHandler(output))
                        }
                }

            let channel = try await bootstrap.bind(host: host, port: Int(port)).get()
            try await closure()
            try await channel.close()
            try await group.shutdownGracefully()
        } catch {
            try await group.shutdownGracefully()
            throw error
        }
    }
}

import NIO
import NIOHTTP1

final class HTTPHandler: ChannelInboundHandler {
    public typealias InboundIn = HTTPServerRequestPart
    public typealias OutboundOut = HTTPServerResponsePart

    private enum State {
        case idle
        case waitingForRequestBody
        case sendingResponse

        mutating func requestReceived() {
            precondition(self == .idle, "Invalid state for request received: \(self)")
            self = .waitingForRequestBody
        }

        mutating func requestComplete() {
            precondition([.waitingForRequestBody, .sendingResponse].contains(self), "Invalid state for request complete: \(self)")
            self = .sendingResponse
        }

        mutating func responseComplete() {
            precondition(self == .sendingResponse, "Invalid state for response complete: \(self)")
            self = .idle
        }
    }

    let output: Data

    private var state: State = .idle
    var receivedBytes: Int = .zero

    init(_ output: Data) {
        self.output = output
    }

    public func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let request = self.unwrapInboundIn(data)

        switch request {
        case .head(let head):
            state.requestReceived()
            var response = HTTPResponseHead(
                version: head.version,
                status: HTTPResponseStatus.ok
            )

            context.write(wrapOutboundOut(.head(response)), promise: nil)
        case .body(let bytes):
            state.requestComplete()
            receivedBytes += bytes.readableBytes
        case .end:
            state.responseComplete()
            let data = (try? JSONSerialization.jsonObject(
                with: output,
                options: [.fragmentsAllowed]
            )).flatMap {
                var dictionary = ($0 as? [String: Any]) ?? [:]

                if dictionary.isEmpty {
                    dictionary["output"] = $0
                }

                dictionary["received_bytes"] = receivedBytes

                return try? JSONSerialization.data(
                    withJSONObject: dictionary,
                    options: [.fragmentsAllowed]
                )
            }

            let sendData = data ?? output
            let buffer = ByteBuffer(bytes: sendData)

            var headers = HTTPHeaders()
            headers.add(name: "content-length", value: "\(sendData.count)")

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
