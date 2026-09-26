//
// See LICENSE for this package's licensing information.
//

// `Internals.ClientManager.client(provider:sessionConfiguration:)` (and the `Internals.Client`
// it returns) only exist under `canImport(NIOCore)`; `.urlSession` goes through
// `resolvedClient(provider:sessionConfiguration:)` instead, covered by
// `InternalsClientManagerExecutorTests`.
#if canImport(NIOCore)

import AsyncHTTPClient
import NIOCore
import NIOPosix
import SwiftAsyncTesting
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

// `ContinuousClock` needs macOS 13/iOS 16/tvOS 16/watchOS 9, newer than this package's macOS
// 12/iOS 15/tvOS 15/watchOS 8 floor -- same reasoning as `Internals.ResourceDeadline`.
#if canImport(Darwin)
import struct Foundation.DispatchTime
#endif

@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsClientManagerTests {

    @Test
    func manager_whenRegister_shouldBeEqual() async throws {
        // Given: this manager's own table, not `.shared`. What is under test is that one
        // configuration reuses its own client, and `.shared` is a process-wide pool every other
        // suite writes into concurrently — `LocalServerConcurrencyTests` alone pushes 200
        // distinct providers through it, enough to evict this entry between the two calls below.
        let manager = Internals.ClientManager(lifetime: Internals.ClientManager.lifetime)
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Internals.Session.Configuration()

        // When
        let sut1 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        let sut2 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        // Then
        #expect(sut1 === sut2)
    }

    @Test
    func manager_whenRegisterWithDifferentConfiguration_shouldBeNotEqual() async throws {
        // Given: an isolated table, same reason as the test above.
        let manager = Internals.ClientManager(lifetime: Internals.ClientManager.lifetime)
        let provider = Internals.SharedSessionProvider()

        let sessionConfiguration1 = Internals.Session.Configuration()

        var sessionConfiguration2 = Internals.Session.Configuration()
        sessionConfiguration2.timeout.connect = 1_000_000_000_000

        // When
        let sut1 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration1
        )

        let sut2 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration2
        )

        // Then
        #expect(sut1 !== sut2)
    }

    @Test
    func manager_expiringClients() async throws {
        // Given
        let lifetime: Int64 = 2_500_000_000
        let manager = Internals.ClientManager(lifetime: lifetime)
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Internals.Session.Configuration()

        // When
        let sut1 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime) * 3)

        let sut2 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        // Then
        #expect(sut1 !== sut2)
    }

    // MARK: - Table bounds

    /// `_table` used to have no ceiling at all, so a workload producing configurations that never
    /// compare equal to a pooled one grew it forever — and made every `_reusableItem` scan, which
    /// is linear, walk the whole accumulated list on the way to finding nothing.
    @Test
    func manager_whenManyDistinctConfigurationsAreRegistered_shouldNotGrowPastMaximumCount() async throws {
        // Given
        let maximumCount = 8
        let manager = Internals.ClientManager(
            lifetime: 5 * 60 * 1_000_000_000,
            maximumCount: maximumCount
        )
        let provider = Internals.SharedSessionProvider()

        // When: every configuration differs, so none of them can ever reuse another's client.
        for index in 0..<(maximumCount * 4) {
            var sessionConfiguration = Internals.Session.Configuration()
            sessionConfiguration.timeout.connect = Int64(1_000_000_000 + index)

            _ = try await manager.client(
                provider: provider,
                sessionConfiguration: sessionConfiguration
            )
        }

        // Then
        #expect(manager.count <= maximumCount)
    }

    /// The ceiling is a bound on bookkeeping, never a gate on service.
    ///
    /// Only an idle client is ever a candidate for eviction, so a table whose every entry is
    /// mid-request has nothing to give up. What must *not* happen then is the caller waiting for
    /// one to free up, being refused, or having a live request's connections torn down to make
    /// room: a request in hand always wins over the ceiling, which the periodic `lifetime` sweep
    /// and the next idle insert bring back down anyway.
    @Test
    func manager_whenEveryPooledClientIsBusy_shouldStillHandOutANewClientImmediately() async throws {
        try await withHangingTCPServer { port in
            // Given: a table filled to its ceiling, with every single entry mid-request.
            let maximumCount = 2
            let manager = Internals.ClientManager(
                lifetime: 5 * 60 * 1_000_000_000,
                maximumCount: maximumCount
            )
            let provider = Internals.SharedSessionProvider()

            var busy = [Internals.Client]()

            // Held for the duration: dropping the handle releases the request's `TaskSeed`,
            // which tears the request down and makes its client idle again -- the very state
            // this test needs never to happen.
            var inFlight = [Internals.UnsafeTask<HTTPClient.Response>]()

            for index in 0..<maximumCount {
                var sessionConfiguration = Internals.Session.Configuration()
                sessionConfiguration.timeout.connect = Int64(60_000_000_000 + index)

                let client = try await manager.client(
                    provider: provider,
                    sessionConfiguration: sessionConfiguration
                )

                // The server accepts and then says nothing, so this stays in flight for the rest
                // of the test rather than racing it.
                inFlight.append(
                    try await client.execute(
                        request: try HTTPClient.Request(url: "http://127.0.0.1:\(port)/"),
                        logger: nil
                    )
                )

                busy.append(client)
            }

            #expect(busy.allSatisfy { $0.isRunning })
            #expect(manager.count == maximumCount)

            // When: one more distinct configuration arrives with no room left for it.
            var overflowing = Internals.Session.Configuration()
            overflowing.timeout.connect = 90_000_000_000

            #if canImport(Darwin)
            let start = DispatchTime.now().uptimeNanoseconds
            #else
            let start = ContinuousClock.now
            #endif

            let overflow = try await manager.client(
                provider: provider,
                sessionConfiguration: overflowing
            )

            // Then: served straight away, the ceiling overshot rather than enforced, and nothing
            // in flight was torn down to get there.
            #if canImport(Darwin)
            #expect(DispatchTime.now().uptimeNanoseconds - start < 1_000_000_000)
            #else
            #expect(ContinuousClock.now - start < .seconds(1))
            #endif
            #expect(manager.count == maximumCount + 1)
            #expect(busy.allSatisfy { $0.isRunning })
            #expect(!overflow.isRunning)

            for task in inFlight {
                task().callAsFunction()
            }
        }
    }

    /// A client handed out but not yet used looks exactly like an idle pooled one: `isRunning`
    /// only becomes `true` once a request is actually asked of it. Evicting *and shutting down*
    /// on that basis raced every caller in the gap between resolving a client and executing
    /// through it, which a 200-session burst hit for real
    /// (`LocalServerConcurrencyTests`, `HTTPClientError.alreadyShutdown`).
    ///
    /// Un-caching it is fine — the caller's own reference keeps it alive, and
    /// `Internals.Client.deinit` retires it afterwards.
    @Test
    func manager_whenEvictingAnIdleClientSomeoneStillHolds_shouldNotShutItDown() async throws {
        // Given: a client resolved but not yet used — idle, and the oldest entry in the table,
        // so the first thing any eviction reaches for.
        let maximumCount = 2
        let manager = Internals.ClientManager(
            lifetime: 5 * 60 * 1_000_000_000,
            maximumCount: maximumCount
        )
        let provider = Internals.SharedSessionProvider()

        var resolved = Internals.Session.Configuration()
        resolved.timeout.connect = 60_000_000_000

        let held = try await manager.client(provider: provider, sessionConfiguration: resolved)
        #expect(!held.isRunning)

        // When: enough other configurations arrive to push it out of the table.
        for index in 0..<(maximumCount * 3) {
            var sessionConfiguration = Internals.Session.Configuration()
            sessionConfiguration.timeout.connect = Int64(1_000_000_000 + index)

            _ = try await manager.client(
                provider: provider,
                sessionConfiguration: sessionConfiguration
            )
        }

        #expect(manager.count <= maximumCount)

        // A shutdown started by the eviction would run detached, so give one time to land rather
        // than racing it to the assertion below.
        try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

        // Then: nothing closed it behind the caller's back. `shutdown()` answers `true` only when
        // *this* call is what actually closed the client.
        #expect(try await held.shutdown())
    }

    /// `Internals.RedirectConfiguration.==` answers `false` for `.strategy` against everything,
    /// itself included, so a pooled `.strategy` entry can never be handed back to anyone and the
    /// linear scan looking for one is guaranteed to walk the whole list and find nothing.
    ///
    /// The entry is still *stored*: the table is also what owns a client for its lifetime, and a
    /// `.nio` client tears its connections down as soon as the last reference to it goes, which
    /// is well before the response body still streaming over them is finished.
    @Test
    func manager_whenConfigurationCarriesARedirectStrategy_shouldNotBeReusedButStillTracked() async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()

        var sessionConfiguration = Internals.Session.Configuration()
        sessionConfiguration.redirectConfiguration = .strategy(NeverFollowingRedirectStrategy())

        // When
        let sut1 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        let sut2 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        // Then: a fresh client either way (that part never worked), each still retained by the
        // table so it outlives the caller's own reference to it.
        #expect(sut1 !== sut2)
        #expect(manager.count == 2)
    }

    /// The ordinary configuration still pools, so the short-circuit above can't have been written
    /// too broadly.
    @Test
    func manager_whenConfigurationCarriesNoRedirectStrategy_shouldStillBePooled() async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()

        var sessionConfiguration = Internals.Session.Configuration()
        sessionConfiguration.redirectConfiguration = .follow(max: 5, allowCycles: false)

        // When
        let sut1 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        let sut2 = try await manager.client(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        // Then
        #expect(sut1 === sut2)
        #expect(manager.count == 1)
    }

    /// `cleanupIfNeeded()` was rewritten to decide first and shut down after, so that several
    /// expired clients drain concurrently instead of one `await` at a time inside `lock` — which
    /// every client resolution in the process also has to take.
    ///
    /// Whether the drains genuinely overlap isn't crisply observable from here (nothing lets a
    /// test hold one client's shutdown open), so this pins the behaviour the rewrite had to
    /// preserve: a backlog of expired clients is still fully retired in one sweep.
    @Test
    func manager_whenSeveralClientsExpire_shouldRetireAllOfThemInOneSweep() async throws {
        // Given: a lifetime long enough that creating the clients cannot itself outlast it, even
        // on a machine busy running the rest of the suite. Shorter ones (250ms, then 2s) both let
        // the first sweep fire mid-setup under a full-suite run.
        let lifetime: Int64 = 5_000_000_000
        let manager = Internals.ClientManager(lifetime: lifetime)
        let provider = Internals.SharedSessionProvider()

        let clientCount = 4

        for index in 0..<clientCount {
            var sessionConfiguration = Internals.Session.Configuration()
            sessionConfiguration.timeout.connect = Int64(1_000_000_000 + index)

            _ = try await manager.client(
                provider: provider,
                sessionConfiguration: sessionConfiguration
            )
        }

        #expect(manager.count == clientCount)

        // When: the scheduled sweep fires, once everything has been idle past `lifetime`. Polled
        // rather than slept through: the sweep is a detached `.utility` task, so when exactly it
        // gets to run is up to the scheduler, and a fixed sleep only ever encodes a guess about
        // how contended the machine is.
        var remaining = manager.count
        for _ in 0..<200 where remaining > 0 {
            try await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
            remaining = manager.count
        }

        // Then
        #expect(remaining == 0)
    }

    @Test
    func manager_whenCallingTaskIsCancelledBeforeItRuns_shouldThrowCancellationError() async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Internals.Session.Configuration()

        // When
        // `AsyncLock` never aborts acquisition, so this only fails if `client(provider:
        // sessionConfiguration:)` checks cancellation itself once inside the lock.
        let task = _Concurrency.Task<Internals.Client, Error> {
            try await manager.client(
                provider: provider,
                sessionConfiguration: sessionConfiguration
            )
        }
        task.cancel()

        // Then
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}

/// Runs `body` against a TCP listener that accepts connections and then says nothing at all.
///
/// A request sent here stays genuinely in flight — `Internals.Client.isRunning` stays `true` —
/// for as long as the test needs, instead of racing it to completion the way a request to a real
/// or an unreachable endpoint would.
private func withHangingTCPServer<Result>(
    _ body: (Int) async throws -> Result
) async throws -> Result {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    let channel = try await ServerBootstrap(group: group)
        .serverChannelOption(ChannelOptions.backlog, value: 256)
        // No handlers at all: whatever arrives is simply never answered.
        .childChannelInitializer { $0.eventLoop.makeSucceededVoidFuture() }
        .bind(host: "127.0.0.1", port: 0)
        .get()

    do {
        let result = try await body(channel.localAddress?.port ?? 0)
        try? await channel.close()
        try? await group.shutdownGracefully()
        return result
    } catch {
        try? await channel.close()
        try? await group.shutdownGracefully()
        throw error
    }
}

/// Only has to exist: `Internals.RedirectConfiguration.==` never looks at what a `.strategy`
/// carries, it answers `false` for the case itself.
private struct NeverFollowingRedirectStrategy: Internals.RedirectStrategy {

    func redirectDecision(for context: Internals.RedirectContext) throws -> Internals.RedirectDecision {
        .doNotFollow
    }
}

#endif
