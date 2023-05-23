/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIO
import NIOSSL
import NIOHTTP1
@testable import RequestDL

struct InternalServer<Response: Codable> where Response: Equatable {

    let host: String
    let port: UInt
    let tlsConfiguration: TLSConfiguration
    let response: Response
    let noCache: Bool
    let maxAge: Bool

    init(
        host: String,
        port: UInt,
        response: Response,
        noCache: Bool = false,
        maxAge: Bool = true,
        option: Option? = nil
    ) throws {
        self.host = host
        self.port = port
        self.response = response
        self.noCache = noCache
        self.maxAge = maxAge

        switch option {
        case .none:
            tlsConfiguration = try Self.makeDefaultTLSConfiguration()
        case .psk(let key, let identity):
            var tlsConfiguration: TLSConfiguration = .makePreSharedKeyConfiguration()
            tlsConfiguration.minimumTLSVersion = .tlsv1
            tlsConfiguration.maximumTLSVersion = .tlsv12

            tlsConfiguration.pskServerCallback = { hint, clientIdentity in
                var bytes = NIOSSLSecureBytes()
                bytes.append(key)
                bytes.append(":\(identity)".utf8)
                bytes.append(":\(clientIdentity)".utf8)
                bytes.append(":\(hint)".utf8)
                return .init(key: bytes)
            }
            tlsConfiguration.pskHint = "pskHint"

            self.tlsConfiguration = tlsConfiguration
        case .client(let client):
            var tlsConfiguration = try Self.makeDefaultTLSConfiguration()
            tlsConfiguration.trustRoots = .file(client.certificateURL.absolutePath(percentEncoded: false))
            tlsConfiguration.certificateVerification = .noHostnameVerification
            self.tlsConfiguration = tlsConfiguration
        }
    }
}

extension InternalServer {

    func run(_ closure: (String) async throws -> Void) async throws {
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        let sslContext = try NIOSSLContext(configuration: tlsConfiguration)

        let futureChannel = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline
                    .addHandlers([
                        BackPressureHandler(),
                        NIOSSLServerHandler(context: sslContext)
                    ])
                    .flatMap {
                        channel.pipeline.configureHTTPServerPipeline()
                    }
                    .flatMap {
                        channel.pipeline.addHandler(HTTPHandler(
                            response: response,
                            noCache: noCache,
                            maxAge: maxAge
                        ))
                    }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
            .bind(host: host, port: Int(port))

        do {
            let channel = try await futureChannel.get()

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

extension InternalServer {

    enum Option {
        case client(CertificateResource)
        case psk(Data, String)
    }

    static func makeDefaultTLSConfiguration() throws -> NIOSSL.TLSConfiguration {
        let server = Certificates().server()

        return .makeServerConfiguration(
            certificateChain: try NIOSSLCertificate.fromPEMFile(
                server.certificateURL.absolutePath(percentEncoded: false)
            ).map { .certificate($0) },
            privateKey: .file(server.privateKeyURL.absolutePath(percentEncoded: false))
        )
    }
}
