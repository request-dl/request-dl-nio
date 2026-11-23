//
// See LICENSE for this package's licensing information.
//

// Everything here is about `Internals.Client` and the server that sends requests to it, which
// need `NIOCore`. The `.urlSession` half only exists on Darwin.
#if canImport(NIOCore)

import AsyncHTTPClient
import NIOCore
import NIOPosix
@_spi(Testing) import SwiftAsyncStream
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

/// `maximumConcurrentConnections` is a cap on a session, not on whichever client a request happens to
/// get: `Internals.ClientManager` keeps one semaphore for each session provider and limit and hands it
/// to every client it creates for them.
///
/// The requests go through a server that holds each one until the test lets it go, so "in flight" is
/// what the server counts, not what the client believes.
struct InternalsClientManagerSessionLimitTests {

    // MARK: - The cap holds

    /// The configuration that has no pooled client to share: every request gets a client of its own, and
    /// every client used to make a semaphore of its own, so all 50 requests were admitted at once.
    @Test(arguments: Transport.all)
    func limit_whenConfigurationCannotBePooled_holdsAcrossEveryClient(transport: Transport) async throws {
        // Given: a limit of two, a configuration that is never pooled, and 50 requests at once.
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        let configuration = transport.configuration(redirectStrategy: true, maximum: 2)

        try #require(!configuration.isPoolable)

        try await withGatedServer { server in
            let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/"))

            // When
            let requests = (0..<50).map { _ in
                _Concurrency.Task {
                    try await Self.send(through: manager, provider: provider, configuration, to: url)
                }
            }

            // Then: two reached the server and held it, and the other 48 are queued behind the semaphore
            // every client shares. Nothing else can be on its way.
            try await completing(within: 30) { await server.waitUntil { $0.held >= 2 } }

            let semaphore = try #require(
                manager.throttledExecutor(provider: provider, maximumConcurrentConnections: 2)
                    .semaphoreForTesting
            )

            try await semaphore.waitForWaiters(48, timeout: 30)

            #expect(server.snapshot.held == 2)
            #expect(server.snapshot.received == 2)
            #expect(semaphore.availablePermits == 0)

            // And as they go through, never more than two at a time.
            server.releaseAll()

            for request in requests {
                try await request.value
            }

            #expect(server.snapshot.received == 50)
            #expect(server.snapshot.peak == 2)
            #expect(semaphore.availablePermits == 2)
            #expect(manager.count == 0)
        }
    }

    /// What already worked, and still has to: clients that are pooled share the limit as before.
    @Test(arguments: Transport.all)
    func limit_whenConfigurationIsPoolable_stillHoldsAcrossEveryRequest(transport: Transport) async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        let configuration = transport.configuration(redirectStrategy: false, maximum: 2)

        try #require(configuration.isPoolable)

        try await withGatedServer { server in
            let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/"))

            // When
            let requests = (0..<50).map { _ in
                _Concurrency.Task {
                    try await Self.send(through: manager, provider: provider, configuration, to: url)
                }
            }

            // Then
            try await completing(within: 30) { await server.waitUntil { $0.held >= 2 } }

            let semaphore = try #require(
                manager.throttledExecutor(provider: provider, maximumConcurrentConnections: 2)
                    .semaphoreForTesting
            )

            try await semaphore.waitForWaiters(48, timeout: 30)

            #expect(server.snapshot.held == 2)
            #expect(server.snapshot.received == 2)

            server.releaseAll()

            for request in requests {
                try await request.value
            }

            #expect(server.snapshot.received == 50)
            #expect(server.snapshot.peak == 2)

            // One client, kept by the pool, served all of them.
            #expect(manager.count == 1)
        }
    }

    /// Two configurations of one provider that differ in something other than the limit cannot share a
    /// client, and share the limit all the same.
    @Test(arguments: Transport.all)
    func limit_whenConfigurationsDifferInSomethingElse_isSharedByThemAll(transport: Transport) async throws {
        // Given: a pooled configuration and one that never is, both with a limit of one.
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        let pooled = transport.configuration(redirectStrategy: false, maximum: 1)
        let unpooled = transport.configuration(redirectStrategy: true, maximum: 1)

        try await withGatedServer { server in
            let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/"))

            // When: two of each.
            let requests = [pooled, unpooled, pooled, unpooled].map { configuration in
                _Concurrency.Task {
                    try await Self.send(through: manager, provider: provider, configuration, to: url)
                }
            }

            // Then: one is in flight, and the other three wait for it.
            try await completing(within: 30) { await server.waitUntil { $0.held >= 1 } }

            let semaphore = try #require(
                manager.throttledExecutor(provider: provider, maximumConcurrentConnections: 1)
                    .semaphoreForTesting
            )

            try await semaphore.waitForWaiters(3, timeout: 30)
            #expect(server.snapshot.received == 1)

            server.releaseAll()

            for request in requests {
                try await request.value
            }

            #expect(server.snapshot.peak == 1)
        }
    }

    // MARK: - Which limit it is

    /// A provider and a limit make a session: the same pair is one semaphore, and any other is another.
    @Test
    func throttledExecutor_isOneSemaphorePerProviderAndLimit() throws {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let shared = Internals.SharedSessionProvider()
        let named = Internals.IdentifiedSessionProvider(id: "session-limit", numberOfThreads: 1)

        // When
        let first = try #require(
            manager.throttledExecutor(provider: shared, maximumConcurrentConnections: 2).semaphoreForTesting
        )
        let again = try #require(
            manager.throttledExecutor(provider: shared, maximumConcurrentConnections: 2).semaphoreForTesting
        )
        let otherLimit = try #require(
            manager.throttledExecutor(provider: shared, maximumConcurrentConnections: 5).semaphoreForTesting
        )
        let otherProvider = try #require(
            manager.throttledExecutor(provider: named, maximumConcurrentConnections: 2).semaphoreForTesting
        )

        // Then: the same limit of the same provider is shared, and nothing else is, so a session that asks for
        // five is never held to the two another one asked for, and the other way round.
        #expect(first === again)
        #expect(first !== otherLimit)
        #expect(first !== otherProvider)
        #expect(first.availablePermits == 2)
        #expect(otherLimit.availablePermits == 5)
        #expect(manager.throttleCount == 3)
    }

    /// Without a limit there is nothing to wait for, and nothing for the manager to keep.
    @Test(arguments: [nil, 0, -3])
    func throttledExecutor_whenThereIsNoLimit_isUnthrottledAndNotTracked(maximum: Int?) {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)

        // When
        let executor = manager.throttledExecutor(
            provider: Internals.SharedSessionProvider(),
            maximumConcurrentConnections: maximum
        )

        // Then
        #expect(executor.semaphoreForTesting == nil)
        #expect(manager.throttleCount == 0)
    }

    // MARK: - Cancellation

    /// A request that is cancelled while it waits leaves the line, and the slot it never had is not lost
    /// nor taken: the next request gets it as soon as the holder is done.
    @Test(arguments: Transport.all)
    func limit_whenAWaiterIsCancelled_leavesTheQueueAndNoSlotIsLost(transport: Transport) async throws {
        // Given: a limit of one, no pooling, one request holding the slot and one queued behind it.
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        let configuration = transport.configuration(redirectStrategy: true, maximum: 1)

        try await withGatedServer { server in
            let url = try #require(URL(string: "http://127.0.0.1:\(server.port)/"))

            let holder = _Concurrency.Task {
                try await Self.send(through: manager, provider: provider, configuration, to: url)
            }

            try await completing(within: 30) { await server.waitUntil { $0.held >= 1 } }

            let semaphore = try #require(
                manager.throttledExecutor(provider: provider, maximumConcurrentConnections: 1)
                    .semaphoreForTesting
            )

            let queued = _Concurrency.Task {
                try await Self.send(through: manager, provider: provider, configuration, to: url)
            }

            try await semaphore.waitForWaiters(1, timeout: 30)

            // When
            queued.cancel()

            // Then: it is out of the line at once, without the holder having had to finish, and the holder's
            // slot is still the only one.
            try await semaphore.waitForWaiters(0, timeout: 30)

            await #expect(throws: CancellationError.self) {
                _ = try await queued.value
            }

            #expect(semaphore.availablePermits == 0)
            #expect(server.snapshot.received == 1)

            // And once the holder is done the slot is there for whoever asks next: a permit that leaked would
            // leave this request waiting for ever, which `completing` turns into a failure.
            server.releaseAll()
            try await holder.value

            try await completing(within: 30) {
                try await Self.send(through: manager, provider: provider, configuration, to: url)
            }

            #expect(server.snapshot.received == 2)
            #expect(server.snapshot.peak == 1)
        }
    }

    // MARK: - Lifetime

    /// A session's limit lives as long as a client of the session does, and goes with the last one.
    @Test(arguments: [false, true])
    func throttle_whenTheLastClientIsGone_isRemovedBySweep(pooled: Bool) async throws {
        // Given: a client resolved for a session with a limit, and nothing yet asked of it.
        let lifetime: Int64 = 5 * 60 * 1_000_000_000
        let manager = Internals.ClientManager(lifetime: lifetime)
        let provider = Internals.SharedSessionProvider()
        let configuration = Transport.nio.configuration(redirectStrategy: !pooled, maximum: 2)

        var resolved: Internals.ClientManager.Client? = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: configuration
        )

        #expect(manager.throttleCount == 1)
        #expect(manager.count == (pooled ? 1 : 0))

        // When: the caller lets go of it, and the pool does when the sweep finds it idle for too long.
        resolved = nil
        await manager.cleanupIfNeeded(at: Self.instant(after: lifetime))

        // Then
        #expect(manager.count == 0)
        #expect(manager.throttleCount == 0)
        withExtendedLifetime(resolved) {}
    }

    /// While the pool still keeps a client, its limit has to stay, or the next client would not share it.
    @Test
    func throttle_whileAClientIsPooled_survivesTheSweep() async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        let configuration = Transport.nio.configuration(redirectStrategy: false, maximum: 2)

        _ = try await manager.resolvedClient(provider: provider, sessionConfiguration: configuration)
        let semaphore = try #require(
            manager.throttledExecutor(provider: provider, maximumConcurrentConnections: 2).semaphoreForTesting
        )

        // When
        await manager.cleanupIfNeeded()

        // Then
        #expect(manager.count == 1)
        #expect(manager.throttleCount == 1)
        #expect(
            manager.throttledExecutor(provider: provider, maximumConcurrentConnections: 2).semaphoreForTesting
                === semaphore
        )
    }

    /// A limit that went unused is dropped the next time one is added, so a workload that keeps making
    /// new sessions does not make the table grow, even before a sweep gets to it.
    @Test
    func throttle_whenManySessionsComeAndGo_doesNotAccumulate() {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)

        // When: a thousand sessions, each of which is gone as soon as it was asked for.
        for index in 0..<1_000 {
            _ = manager.throttledExecutor(
                provider: Internals.IdentifiedSessionProvider(id: "session-\(index)", numberOfThreads: 1),
                maximumConcurrentConnections: 2
            )
        }

        // Then: at most the one that was added last, which nothing has had the chance to let go of yet.
        #expect(manager.throttleCount <= 1)
    }

    // MARK: - The global lock

    /// A client that is not pooled never touches the table, so building it has no business waiting for the
    /// lock every resolution takes, nor making other resolutions wait while it builds a whole session.
    @Test(arguments: Transport.all)
    func resolvedClient_whenConfigurationCannotBePooled_doesNotWaitForTheResolutionLock(
        transport: Transport
    ) async throws {
        // Given: the lock held, as in the middle of another resolution.
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        let configuration = transport.configuration(redirectStrategy: true, maximum: 2)

        await manager.lock.lock()

        // When
        let resolved: Internals.ClientManager.Client?

        do {
            resolved = try await completing(within: 30) {
                try await manager.resolvedClient(provider: provider, sessionConfiguration: configuration)
            }
        } catch {
            manager.lock.unlock()
            throw error
        }

        manager.lock.unlock()

        // Then
        #expect(resolved != nil)
        #expect(manager.count == 0)
    }

    // MARK: - Private static methods

    private static func send(
        through manager: Internals.ClientManager,
        provider: Internals.SharedSessionProvider,
        _ configuration: Internals.Session.Configuration,
        to url: URL
    ) async throws {
        let resolved = try await manager.resolvedClient(provider: provider, sessionConfiguration: configuration)

        switch resolved {
        case .nio(let client):
            let request = try HTTPClient.Request(url: url.absoluteString)
            let task = try await client.execute(request: request, logger: nil)

            _ = try await task.response()
        #if canImport(Darwin)
        case .urlSession(let client):
            _ = try await client.execute(request: URLRequest(url: url))
        #endif
        }
    }

    /// A moment `nanoseconds` past now, on the clock the sweep reads.
    private static func instant(after nanoseconds: Int64) -> Internals.ClientManager.MonotonicInstant {
        #if canImport(Darwin)
        Internals.ClientManager.monotonicNow() + UInt64(nanoseconds) + 1
        #else
        Internals.ClientManager.monotonicNow().advanced(by: .nanoseconds(nanoseconds + 1))
        #endif
    }
}

// MARK: - Transport

extension InternalsClientManagerSessionLimitTests {

    /// The executor a configuration is made to run on.
    struct Transport: Sendable, CustomTestStringConvertible {

        let executor: Internals.Executor

        var testDescription: String {
            "\(executor)"
        }

        static let nio = Transport(executor: .nio)

        #if canImport(Darwin)
        static let urlSession = Transport(executor: .urlSession)

        static let all = [nio, urlSession]
        #else
        static let all = [nio]
        #endif

        /// - Parameter redirectStrategy: Whether the redirect policy is one that cannot be compared, which is what
        /// keeps a configuration from ever matching a pooled client.
        func configuration(redirectStrategy: Bool, maximum: Int) -> Internals.Session.Configuration {
            var configuration = Internals.Session.Configuration()
            configuration.requiredExecutor = executor
            configuration.maximumConcurrentConnections = maximum

            if redirectStrategy {
                configuration.redirectConfiguration = .strategy(SessionLimitNeverFollowingStrategy())
            }

            return configuration
        }
    }
}

private struct SessionLimitNeverFollowingStrategy: Internals.RedirectStrategy {

    func redirectDecision(for context: Internals.RedirectContext) throws -> Internals.RedirectDecision {
        .doNotFollow
    }
}

// MARK: - Server

/// Runs `body` against a server that reads each request and holds its answer until the test lets it go.
///
/// A request stays in flight for exactly as long as the test wants, and the server is where "in flight"
/// is counted: a request is held from the moment its head arrived until it was answered.
private func withGatedServer<Result>(
    _ body: (GatedServer) async throws -> Result
) async throws -> Result {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    let server = GatedServer()

    let channel = try await ServerBootstrap(group: group)
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        .childChannelInitializer { channel in
            channel.pipeline.addHandler(GatedServerHandler(server: server))
        }
        .bind(host: "127.0.0.1", port: 0)
        .get()

    server.port = channel.localAddress?.port ?? 0

    do {
        let result = try await body(server)
        server.releaseAll()
        try? await channel.close()
        try? await group.shutdownGracefully()
        return result
    } catch {
        server.releaseAll()
        try? await channel.close()
        try? await group.shutdownGracefully()
        throw error
    }
}

private final class GatedServer: @unchecked Sendable {

    struct Snapshot: Sendable {

        /// Requests whose head arrived.
        var received = 0

        /// Requests that arrived and have not been answered.
        var held = 0

        /// The most `held` ever was.
        var peak = 0

        var released = false
    }

    private struct Waiter {
        let predicate: @Sendable (Snapshot) -> Bool
        let continuation: CheckedContinuation<Void, Never>
    }

    private struct State {
        var snapshot = Snapshot()
        var channels = [Channel]()
        var waiters = [Waiter]()
    }

    // MARK: - Internal properties

    var port = 0

    var snapshot: Snapshot {
        state.withLockedValue { $0.snapshot }
    }

    // MARK: - Private properties

    private let state = LockedValueBox(State())

    // MARK: - Internal methods

    /// Returns when `predicate` holds, without polling: every change to the counters looks at who is waiting.
    func waitUntil(_ predicate: @escaping @Sendable (Snapshot) -> Bool) async {
        await withCheckedContinuation { continuation in
            let satisfied = state.withLockedValue { state -> Bool in
                guard !predicate(state.snapshot) else {
                    return true
                }

                state.waiters.append(Waiter(predicate: predicate, continuation: continuation))
                return false
            }

            if satisfied {
                continuation.resume()
            }
        }
    }

    /// Answers everything held, and everything that arrives from now on straight away.
    func releaseAll() {
        let channels = state.withLockedValue { state -> [Channel] in
            state.snapshot.released = true

            defer { state.channels = [] }
            return state.channels
        }

        for channel in channels {
            respond(on: channel)
        }
    }

    // MARK: - Fileprivate methods

    fileprivate func requestArrived(on channel: Channel) {
        let respondNow = state.withLockedValue { state -> Bool in
            state.snapshot.received += 1
            state.snapshot.held += 1
            state.snapshot.peak = max(state.snapshot.peak, state.snapshot.held)

            if !state.snapshot.released {
                state.channels.append(channel)
            }

            return state.snapshot.released
        }

        notify()

        if respondNow {
            respond(on: channel)
        }
    }

    // MARK: - Private methods

    private func respond(on channel: Channel) {
        let body = "ok"
        let head = "HTTP/1.1 200 OK\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"

        channel.eventLoop.execute {
            var buffer = channel.allocator.buffer(capacity: head.utf8.count)
            buffer.writeString(head)

            channel.writeAndFlush(buffer).whenComplete { _ in
                self.state.withLockedValue { $0.snapshot.held -= 1 }
                self.notify()

                channel.close(promise: nil)
            }
        }
    }

    private func notify() {
        let ready = state.withLockedValue { state -> [Waiter] in
            let ready = state.waiters.filter { $0.predicate(state.snapshot) }
            state.waiters = state.waiters.filter { !$0.predicate(state.snapshot) }

            return ready
        }

        for waiter in ready {
            waiter.continuation.resume()
        }
    }
}

private final class GatedServerHandler: ChannelInboundHandler, @unchecked Sendable {

    typealias InboundIn = ByteBuffer

    private let server: GatedServer
    private var received = ""
    private var arrived = false

    init(server: GatedServer) {
        self.server = server
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !arrived else {
            return
        }

        received += unwrapInboundIn(data).getString(at: 0, length: unwrapInboundIn(data).readableBytes) ?? ""

        guard received.contains("\r\n\r\n") else {
            return
        }

        arrived = true
        server.requestArrived(on: context.channel)
    }
}

#endif
