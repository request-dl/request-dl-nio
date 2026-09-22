//
// See LICENSE for this package's licensing information.
//

// `Internals.ClientManager.client(provider:sessionConfiguration:)` (and the `Internals.Client`
// it returns) only exist under `canImport(NIOCore)`; `.urlSession` goes through
// `resolvedClient(provider:sessionConfiguration:)` instead, covered by
// `InternalsClientManagerExecutorTests`.
#if canImport(NIOCore)

import SwiftAsyncTesting
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsClientManagerTests {

    @Test
    func manager_whenRegister_shouldBeEqual() async throws {
        // Given
        let manager = Internals.ClientManager.shared
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
        // Given
        let manager = Internals.ClientManager.shared
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

    /// `Internals.RedirectConfiguration.==` answers `false` for `.strategy` against everything,
    /// itself included, so a pooled `.strategy` entry can never be handed back to anyone. Caching
    /// it is pure cost, paid by every later scan.
    @Test
    func manager_whenConfigurationCarriesARedirectStrategy_shouldNotBePooled() async throws {
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

        // Then: a fresh client either way (that part never worked), but now without leaving an
        // unusable entry behind for every resolution.
        #expect(sut1 !== sut2)
        #expect(manager.count == 0)
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
        // Given
        let lifetime: Int64 = 250_000_000
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

        // When: the scheduled sweep fires once everything has been idle past `lifetime`.
        try await _Concurrency.Task.sleep(nanoseconds: UInt64(lifetime) * 4)

        // Then
        #expect(manager.count == 0)
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

/// Only has to exist: `Internals.RedirectConfiguration.==` never looks at what a `.strategy`
/// carries, it answers `false` for the case itself.
private struct NeverFollowingRedirectStrategy: Internals.RedirectStrategy {

    func redirectDecision(for context: Internals.RedirectContext) throws -> Internals.RedirectDecision {
        .doNotFollow
    }
}

#endif
