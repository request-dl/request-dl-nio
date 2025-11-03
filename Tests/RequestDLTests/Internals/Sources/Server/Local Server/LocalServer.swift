/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIO
import NIOSSL
import NIOHTTP1
#if os(iOS) || os(tvOS) || os(macOS) || os(watchOS) || os(visionOS)
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

        func remove(_ configuration: Configuration) async throws {
            try await _channels[configuration]?.0.close()
            _channels[configuration] = nil
        }

        func channel(_ configuration: Configuration) async throws -> (Channel, ResponseQueue) {
            try await lock.withLock {
                if let output = _channels[configuration] {
                    return output
                }

                guard
                    !_channels.keys.contains(where: {
                        $0.host == configuration.host &&
                        $0.port == configuration.port
                    })
                else { fatalError() }

                let tlsConfiguration = try configuration.option.build()
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
                    .bind(host: configuration.host, port: Int(configuration.port))

                let channel = try await futureChannel.get()
                _channels[configuration] = (channel, responseQueue)
                return (channel, responseQueue)
            }
        }
    }

    final class ResponseQueue: @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _responses: [ResponseConfiguration] = []

        // MARK: - Inits

        init() {}

        // MARK: - Internal methods

        func insert(_ response: ResponseConfiguration) {
            lock.withLock {
                _responses.insert(response, at: .zero)
            }
        }

        func popLast() -> ResponseConfiguration? {
            lock.withLock {
                _responses.popLast()
            }
        }

        func cleanup() {
            lock.withLock {
                _responses = []
            }
        }
    }

    // MARK: - Private properties

    private let configuration: Configuration
    private let channel: Channel
    private let responseQueue: ResponseQueue

    // MARK: - Inits

    init(_ configuration: Configuration) async throws {
        let (channel, responseQueue) = try await ServerManager.shared.channel(configuration)

        self.configuration = configuration
        self.channel = channel
        self.responseQueue = responseQueue
    }

    func insert(_ response: ResponseConfiguration) {
        responseQueue.insert(response)
    }

    func cleanup() {
        responseQueue.cleanup()
    }

    var baseURL: String {
        configuration.host + ":" + String(configuration.port)
    }
}
