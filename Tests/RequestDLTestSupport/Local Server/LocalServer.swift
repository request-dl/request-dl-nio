//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

#if canImport(NIOCore)

import NIO
import NIOHTTP1
import NIOSSL

@testable import RequestDL

#if canImport(Darwin)
import NIOTransportServices
#endif

#endif

struct LocalServer: Sendable {

    /// The resource one `ServerManager` entry keeps alive for a `Configuration`: a NIOSSL/
    /// `ServerBootstrap`-backed `Channel` when this target has `NIOCore`, or a Network.framework
    /// `PortableServer` when it doesn't (see `LocalServer.PortableServer.swift`). Both expose
    /// `close() async throws`, which is all `ServerManager` itself needs.
    #if canImport(NIOCore)
    typealias ServerHandle = Channel
    #else
    typealias ServerHandle = PortableServer
    #endif

    final class ServerManager: @unchecked Sendable {

        // MARK: - Internal static properties

        static let shared = ServerManager()

        // Separate instance (own `group`/`_servers`) for LocalServerConcurrencyTests' 200
        // -connection burst, paired with `Configuration.stress` (see LocalServer.Configuration.swift)
        // so that deliberate stress test no longer competes with every other LocalServer-backed
        // suite for `.shared`'s threads.
        static let stress = ServerManager()

        // MARK: - Private properties

        private let lock = AsyncLock()

        #if canImport(NIOCore)
        // Shared process-wide across every suite that spins up a LocalServer (DataTaskTests,
        // DownloadTaskTests, UploadTaskTests, InternalsSessionTests, ModifiersCollect*Tests,
        // CachedRequestTests, ...). swift-testing runs suites concurrently by default, so too few
        // threads here queues every concurrent suite's TLS handshakes behind each other —
        // tolerable on lighter simulators, not on visionOS (see InternalsSessionTests'
        // connectTimeout/tlsHandshakeTimeout failures in visionOS CI).
        //
        // Bumped from 1 to 4 threads previously (see git history), which held up until a CI run
        // with unusually heavy shared-runner contention (ci-triage/TASKS.md T4) reproduced the
        // same connectTimeout on both `InternalsSessionTests.session_whenPerformingGet_shouldBeValid`
        // and, independently, `LocalServerConcurrencyTests.manyConcurrentSessions_
        // shareLocalServerWithoutCrossTalkOrHanging` itself — the latter alone drives 200
        // concurrently-connecting client sessions at this same group. Bumped again to 8; still a
        // fixed headroom guess rather than a guarantee against arbitrarily bad contention, so a
        // recurrence here should widen this further rather than be treated as a new bug.
        //
        // LocalServerConcurrencyTests has since moved its 200-connection burst to `.stress`
        // (its own instance, own group, `Configuration.stress`/port 8889) instead of driving
        // that load at this shared group — this group's remaining exposure is the aggregate of
        // every *other* LocalServer-backed suite's normal (light) traffic.
        private let group = MultiThreadedEventLoopGroup(numberOfThreads: 8)
        #endif

        // MARK: - Unsafe properties

        private var _servers: [Configuration: (ServerHandle, ResponseQueue)] = [:]

        // MARK: - Internal methods

        func remove(_ serverConfiguration: Configuration) async throws {
            try await _servers[serverConfiguration]?.0.close()
            _servers[serverConfiguration] = nil
        }

        func resolve(_ serverConfiguration: Configuration) async throws -> (ServerHandle, ResponseQueue) {
            try await lock.withLock {
                if let output = _servers[serverConfiguration] {
                    return output
                }

                guard
                    !_servers.keys.contains(where: {
                        $0.host == serverConfiguration.host && $0.port == serverConfiguration.port
                    })
                else { fatalError() }

                let responseQueue = ResponseQueue()

                #if canImport(NIOCore)
                let tlsConfiguration = try serverConfiguration.option.build()
                let sslContext = try NIOSSLContext(configuration: tlsConfiguration)

                let futureChannel = ServerBootstrap(group: group)
                    .serverChannelOption(ChannelOptions.backlog, value: 256)
                    .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                    .childChannelInitializer { channel in
                        channel.pipeline
                            .addHandlers([
                                BackPressureHandler(),
                                NIOSSLServerHandler(context: sslContext),
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

                let handle = try await futureChannel.get()
                #else
                let handle = try await PortableServer(
                    configuration: serverConfiguration,
                    responseQueue: responseQueue
                )
                #endif

                _servers[serverConfiguration] = (handle, responseQueue)
                return (handle, responseQueue)
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
    private let serverHandle: ServerHandle
    private let responseQueue: ResponseQueue

    // MARK: - Inits

    init(_ serverConfiguration: Configuration, manager: ServerManager = .shared) async throws {
        let (serverHandle, responseQueue) = try await manager.resolve(serverConfiguration)

        self.serverConfiguration = serverConfiguration
        self.serverHandle = serverHandle
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
