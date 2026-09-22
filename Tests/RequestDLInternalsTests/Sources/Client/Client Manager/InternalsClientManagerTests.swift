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

    /// Regression coverage for a pooled-client cache collision: `Internals.Proxy.connectHeaders`
    /// used to be excluded from `Hashable`, so `Internals.Session.Configuration.==` (this
    /// manager's cache key) treated two sessions whose proxy differed only in CONNECT headers as
    /// interchangeable. `connectHeaders` is commonly where proxy-auth secrets distinct per
    /// session live, so sharing a pooled client here would silently carry one session's proxy
    /// credentials into a request meant for a different one's.
    @Test
    func manager_whenRegisterWithDifferentProxyConnectHeaders_shouldBeNotEqual() async throws {
        // Given
        let manager = Internals.ClientManager.shared
        let provider = Internals.SharedSessionProvider()

        var firstConnectHeaders = Internals.HTTPHeaders()
        firstConnectHeaders.add(name: "Proxy-Authorization", value: "Bearer first-session-token")

        var secondConnectHeaders = Internals.HTTPHeaders()
        secondConnectHeaders.add(name: "Proxy-Authorization", value: "Bearer second-session-token")

        var sessionConfiguration1 = Internals.Session.Configuration()
        sessionConfiguration1.proxy = .init(
            host: "proxy.example.com",
            port: 8_080,
            connection: .http,
            authorization: nil,
            connectHeaders: firstConnectHeaders
        )

        var sessionConfiguration2 = Internals.Session.Configuration()
        sessionConfiguration2.proxy = .init(
            host: "proxy.example.com",
            port: 8_080,
            connection: .http,
            authorization: nil,
            connectHeaders: secondConnectHeaders
        )

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

    /// Regression coverage for a pooled-client cache collision: `Internals.Decompression.==`
    /// used to compare only the set of `Content-Encoding` values, so a session configured with a
    /// custom algorithm declaring `"gzip"` was indistinguishable from one configured with the
    /// built-in placeholder for `async-http-client`'s own gzip decoding. The two need opposite
    /// `HTTPClient.Decompression` settings, which `Internals.Session.Configuration.build()` bakes
    /// into the client at construction, so sharing one here would either double-decode the custom
    /// session's body or leave the native session's body compressed.
    @Test
    func manager_whenRegisterWithDifferentDecompressionAlgorithmKinds_shouldBeNotEqual() async throws {
        // Given
        let manager = Internals.ClientManager.shared
        let provider = Internals.SharedSessionProvider()

        var sessionConfiguration1 = Internals.Session.Configuration()
        sessionConfiguration1.decompression = .enabled(
            algorithms: [InternalsDecompressionTests.MockGzipAlgorithm()],
            limit: .none
        )

        var sessionConfiguration2 = Internals.Session.Configuration()
        sessionConfiguration2.decompression = .enabled(
            algorithms: [InternalsDecompressionTests.MockCustomAlgorithmNamedGzip()],
            limit: .none
        )

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

#endif
