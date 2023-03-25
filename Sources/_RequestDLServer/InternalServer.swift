/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIO
import NIOSSL
import NIOHTTP1

public struct InternalServer<Response: Codable> where Response: Equatable {

    let host: String
    let port: UInt
    let tlsConfiguration: TLSConfiguration
    let response: Response

    public init(
        host: String,
        port: UInt,
        response: Response
    ) throws {
        let server = Certificates().server()

        self.host = host
        self.port = port
        self.response = response

        self.tlsConfiguration = .makeServerConfiguration(
            certificateChain: try NIOSSLCertificate.fromPEMFile(server.certificateURL.path).map {
                .certificate($0)
            },
            privateKey: .file(server.privateKeyURL.path)
        )
    }
}

extension InternalServer {

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
                            channel.pipeline.addHandler(HTTPHandler(response))
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
