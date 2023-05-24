/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIO
import NIOSSL
import NIOHTTP1
@testable import RequestDL

struct LocalServer: Sendable {

    final class ServerManager: @unchecked Sendable {

        static let shared = ServerManager()

        private let lock = AsyncLock()
        private let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

        private var _channels: [Configuration: (Channel, RequestBag)] = [:]

        func remove(_ configuration: Configuration) async throws {
            try await _channels[configuration]?.0.close()
            _channels[configuration] = nil
        }

        func channel(_ configuration: Configuration) async throws -> (Channel, RequestBag) {
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
                let bag = RequestBag()

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
                                channel.pipeline.addHandler(HTTPHandler(bag))
                            }
                    }
                    .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
                    .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())
                    .bind(host: configuration.host, port: Int(configuration.port))

                let channel = try await futureChannel.get()
                _channels[configuration] = (channel, bag)
                return (channel, bag)
            }
        }
    }

    final class RequestBag: @unchecked Sendable {

        private let lock = Lock()
        private let lockState = AsyncLock()

        private var _pendingConfiguration: ResponseConfiguration?

        init() {}

        func register(_ configuration: ResponseConfiguration) async {
            await lockState.lock()

            lock.withLock {
                _pendingConfiguration = configuration
            }
        }

        func latestConfiguration() -> ResponseConfiguration? {
            lock.withLock {
                _pendingConfiguration
            }
        }

        func consume() {
            lock.withLock {
                _pendingConfiguration = nil
            }

            lockState.unlock()
        }
    }

    private let configuration: Configuration
    private let bag: RequestBag
    private let channel: Channel

    init(_ configuration: Configuration) async throws {
        let (channel, bag) = try await ServerManager.shared.channel(configuration)

        self.configuration = configuration
        self.channel = channel
        self.bag = bag
    }

    func register(_ configuration: ResponseConfiguration) async {
        await bag.register(configuration)
    }

    func releaseConfiguration() {
        bag.consume()
    }

    var baseURL: String {
        configuration.host + ":" + String(configuration.port)
    }
}
