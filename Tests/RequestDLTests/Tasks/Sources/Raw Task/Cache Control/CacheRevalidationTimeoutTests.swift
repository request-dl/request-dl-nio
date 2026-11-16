//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(NIOCore)

import NIOConcurrencyHelpers
import NIOCore
import NIOHTTP1
import NIOPosix
import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
import struct Foundation.UUID
#endif

/// The conditional request that asks whether a cached response still holds goes out before the
/// request itself does, so there is no response yet for `Timeout(_:for: .read)` to cancel. Each of
/// these runs a real request against a server that takes the connection and then says nothing to
/// the `HEAD`.
///
/// The time is not the machine's: each request counts a ``FakeIdleClock`` the test moves.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct CacheRevalidationTimeoutTests {

    private typealias Executor = TransferTestExecutor

    /// The budget every test gives a request, in the fake clock's time.
    private static let budget = UnitTime.seconds(60)

    // MARK: - Server

    /// Answers a `GET` with a small body, and never answers a `HEAD`, unless `answersHead`.
    private final class Server: @unchecked Sendable {

        final class Handler: ChannelInboundHandler, @unchecked Sendable {

            typealias InboundIn = HTTPServerRequestPart
            typealias OutboundOut = HTTPServerResponsePart

            private let server: Server
            private var method: NIOHTTP1.HTTPMethod?

            init(_ server: Server) {
                self.server = server
            }

            func channelRead(context: ChannelHandlerContext, data: NIOAny) {
                switch unwrapInboundIn(data) {
                case .head(let head):
                    method = head.method
                    server.lock.withLock {
                        if head.method == .HEAD {
                            server._heads += 1
                        } else {
                            server._gets += 1
                        }
                    }
                case .body:
                    break
                case .end:
                    guard method != .HEAD || server.answersHead.withLockedValue({ $0 }) else {
                        return
                    }

                    let body = "fresh"
                    var headers = NIOHTTP1.HTTPHeaders()
                    headers.add(name: "Content-Length", value: String(body.utf8.count))
                    headers.add(name: "ETag", value: "\"fresh\"")

                    let head = HTTPResponseHead(version: .http1_1, status: .ok, headers: headers)
                    context.write(wrapOutboundOut(.head(head)), promise: nil)

                    if method != .HEAD {
                        context.write(wrapOutboundOut(.body(.byteBuffer(ByteBuffer(string: body)))), promise: nil)
                    }

                    context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
                }
            }
        }

        let answersHead = LockedValueBox(false)

        var heads: Int {
            lock.withLock { _heads }
        }

        var gets: Int {
            lock.withLock { _gets }
        }

        let port: Int

        fileprivate let lock = NIOLock()
        fileprivate var _heads = 0
        fileprivate var _gets = 0

        private let group: MultiThreadedEventLoopGroup
        private let channel: Channel

        init() async throws {
            let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
            self.group = group

            let holder = LockedValueBox<Server?>(nil)

            channel = try await ServerBootstrap(group: group)
                .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .childChannelInitializer { channel in
                    channel.eventLoop.makeCompletedFuture {
                        try channel.pipeline.syncOperations.configureHTTPServerPipeline()
                        try channel.pipeline.syncOperations.addHandler(Handler(holder.withLockedValue { $0 }!))
                    }
                }
                .bind(host: "127.0.0.1", port: 0)
                .get()

            port = channel.localAddress?.port ?? .zero
            holder.withLockedValue { $0 = self }
        }

        func stop() async {
            try? await channel.close()
            try? await group.shutdownGracefully()
        }
    }

    private func withServer(_ body: (Server) async throws -> Void) async throws {
        let server = try await Server()

        do {
            try await body(server)
        } catch {
            await server.stop()
            throw error
        }

        await server.stop()
    }

    // MARK: - Fixtures

    /// A cache holding a response for `url` that was fresh for an hour, and has a validator, so a
    /// request that asks for it to be validated asks the server.
    private func makeCache(for url: String) async -> DataCache {
        let uniqueKey = UUID().uuidString
        let cache = DataCache(suiteName: uniqueKey)

        await cache.removeAll()
        cache.memoryCapacity = 8 * 1_024 * 1_024
        cache.diskCapacity = 64 * 1_024 * 1_024

        let body = Data("cached".utf8)

        await cache.setCachedData(
            await CachedData(
                response: ResponseHead(
                    url: URL(string: url),
                    status: .init(code: 200, reason: "Ok"),
                    version: .init(minor: 1, major: 1),
                    headers: HTTPHeaders([
                        ("ETag", "\"cached\""),
                        ("Cache-Control", "public, max-age=3600"),
                        ("Content-Length", String(body.count)),
                    ]),
                    isKeepAlive: false
                ),
                policy: .all,
                data: body
            ),
            forKey: url
        )

        return cache
    }

    private final class Running: @unchecked Sendable {

        private let outcome = LockedValueBox<Result<String, any Error>?>(nil)

        var isDone: Bool {
            outcome.withLockedValue { $0 != nil }
        }

        var result: Result<String, any Error>? {
            outcome.withLockedValue { $0 }
        }

        init(_ clock: FakeIdleClock, _ body: @escaping @Sendable () async throws -> String) {
            _Concurrency.Task { [outcome] in
                let result: Result<String, any Error>

                do {
                    result = .success(try await clock.bind(body))
                } catch {
                    result = .failure(error)
                }

                outcome.withLockedValue { $0 = result }
            }
        }
    }

    // MARK: - Tests

    /// A server that takes the conditional request and never answers it ends the request the way
    /// one that goes quiet later does: with `ReadTimeoutError`, once a whole budget has gone by
    /// without a byte.
    @Test(arguments: Executor.allCases)
    private func aRevalidationThatNeverAnswers_failsWithReadTimeoutError(_ executor: Executor) async throws {
        try await withServer { server in
            // Given
            let url = "http://127.0.0.1:\(server.port)/resource"
            let cache = await makeCache(for: url)
            let clock = FakeIdleClock()

            let running = Running(clock) {
                let data = try await DataTask {
                    BaseURL(.http, host: "127.0.0.1:\(server.port)")
                    Path("/resource")
                    executor.pinnedSession
                        .cachePolicy(.all)
                        .cacheStrategy(.reloadAndValidateCachedData)
                        .cache(memoryCapacity: 0, diskCapacity: 0, url: cache.directoryURL)
                    Timeout(Self.budget, for: .read)
                }
                .extractPayload()
                .result()

                return String(decoding: data, as: UTF8.self)
            }

            try await eventually(timeout: 60) { server.heads >= 1 }

            // When: a whole budget goes by.
            await clock.advance(by: Self.budget.nanoseconds, until: { running.isDone })

            // Then
            let result = try #require(running.result, "the request is still waiting for the HEAD")
            #expect(throws: ReadTimeoutError.self) { try result.get() }
            #expect(server.gets == 0)
        }
    }
}

#endif
