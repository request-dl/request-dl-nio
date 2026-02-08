/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIO
import NIOSSL
import NIOHTTP1
#if canImport(Darwin)
import NIOTransportServices
#endif
@testable import RequestDL

struct LocalServer: Sendable {

    final class ServerManager: @unchecked Sendable {

        // MARK: - Internal static properties

        static let shared = ServerManager()

        // MARK: - Private properties

        private let lock = AsyncLock()
        private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        // MARK: - Unsafe properties

        private var _channels: [Configuration: (Channel, ResponseQueue)] = [:]

        // MARK: - Internal methods

        func remove(_ serverConfiguration: Configuration) async throws {
            try await _channels[serverConfiguration]?.0.close()
            _channels[serverConfiguration] = nil
        }

        func channel(_ serverConfiguration: Configuration) async throws -> (Channel, ResponseQueue) {
            try await lock.withLock {
                if let output = _channels[serverConfiguration] {
                    return output
                }

                guard
                    !_channels.keys.contains(where: {
                        $0.host == serverConfiguration.host &&
                        $0.port == serverConfiguration.port
                    })
                else { fatalError() }

                let tlsConfiguration = try serverConfiguration.option.build()
                let sslContext = try NIOSSLContext(configuration: tlsConfiguration)
                let responseQueue = ResponseQueue()

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
                                channel.pipeline.addHandler(HTTPHandler(responseQueue))
                            }
                    }
                    .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
                    .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
                    .bind(host: serverConfiguration.host, port: Int(serverConfiguration.port))

                let channel = try await futureChannel.get()
                _channels[serverConfiguration] = (channel, responseQueue)
                return (channel, responseQueue)
            }
        }
    }

    final class ResponseQueue: @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _responses: [String: [ResponseConfiguration]] = [:]

        // MARK: - Inits

        init() {}

        // MARK: - Internal methods

        func insert(_ response: ResponseConfiguration, at path: String) {
            lock.withLock {
                _responses[path, default: []].insert(response, at: .zero)
            }
        }

        func popLast(at path: String) -> ResponseConfiguration? {
            lock.withLock {
                _responses[path, default: []].popLast()
            }
        }

        func cleanup(at path: String) {
            lock.withLock {
                _responses[path, default: []] = []
            }
        }

        func cleanupAll() {
            lock.withLock {
                _responses = [:]
            }
        }
    }

    // MARK: - Private properties

    private let serverConfiguration: Configuration
    private let channel: Channel
    private let responseQueue: ResponseQueue

    // MARK: - Inits

    init(_ serverConfiguration: Configuration) async throws {
        let (channel, responseQueue) = try await ServerManager.shared.channel(serverConfiguration)

        self.serverConfiguration = serverConfiguration
        self.channel = channel
        self.responseQueue = responseQueue
    }

    func insert(_ response: ResponseConfiguration, at path: String) {
        responseQueue.insert(response, at: path)
    }

    func cleanup(at path: String) {
        responseQueue.cleanup(at: path)
    }

    var baseURL: String {
        serverConfiguration.host + ":" + String(serverConfiguration.port)
    }
}
