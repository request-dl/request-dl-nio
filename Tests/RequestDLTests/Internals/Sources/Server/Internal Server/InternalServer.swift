/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIO
import NIOSSL
import NIOHTTP1

struct InternalServer<Response: Codable> where Response: Equatable {

    let host: String
    let port: UInt
    let tlsConfiguration: TLSConfiguration
    let response: Response

    init(
        host: String,
        port: UInt,
        response: Response,
        disableCAValidation: Bool = true
    ) throws {
        let server = Certificates().server()

        self.host = host
        self.port = port
        self.response = response

        var tlsConfiguration: TLSConfiguration = .makeServerConfiguration(
            certificateChain: try NIOSSLCertificate.fromPEMFile(server.certificateURL.path).map {
                .certificate($0)
            },
            privateKey: .file(server.privateKeyURL.path)
        )

        if !disableCAValidation {
            tlsConfiguration.pskClientCallback = {
                .init(
                    key: .init(try Data(contentsOf: server.pskURL)),
                    identity: $0
                )
            }
        }

        self.tlsConfiguration = tlsConfiguration
    }
}

extension InternalServer {

    func run(_ closure: (String) async throws -> Void) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let sslContext = try NIOSSLContext(configuration: tlsConfiguration)

        let bootstrap = ServerBootstrap(group: group)
            // ① Set up our ServerChannel
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                // ③ add handlers to the pipeline
                channel.pipeline
                    .addHandlers([BackPressureHandler(), NIOSSLServerHandler(context: sslContext)])
                    .flatMap {
                        channel.pipeline.configureHTTPServerPipeline()
                    }
                    .flatMap {
                        channel.pipeline.addHandler(HTTPHandler(response))
                    }
            }
            // ④ Set up child channel options
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
            .bind(host: host, port: Int(port))

        do {
            let channel = try await bootstrap.get()

            do {
                try await closure("\(host):\(port)")
                try await channel.close()
                try await group.shutdownGracefully()
            } catch {
                try await channel.close()
                try await group.shutdownGracefully()
                throw error
            }
        } catch {
            try await group.shutdownGracefully()
            throw error
        }
    }
}
