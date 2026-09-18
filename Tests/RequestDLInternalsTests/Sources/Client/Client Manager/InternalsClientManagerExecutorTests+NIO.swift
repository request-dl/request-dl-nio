//
// See LICENSE for this package's licensing information.
//

// The `.nio`/`.nioTransportServices` half of `InternalsClientManagerExecutorTests` (see the main
// declaration's own doc comment, in `InternalsClientManagerExecutorTests.swift`), split out
// because these tests reach `Internals.ClientManager.Client.nio` and `NIOTSEventLoopGroup`,
// neither of which exists at all without `NIOCore`/`NIOTransportServices` -- i.e. under
// `--disable-default-traits`.
#if canImport(Darwin) && canImport(NIOCore)

import NIOCore
import NIOTransportServices
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

extension InternalsClientManagerExecutorTests {

    @Test
    func resolvedClient_whenConfigurationIsIncompatibleWithURLSession_fallsBackToNIO() async throws {
        // Given: a DNS override is excluded from `.urlSession` (bucket D; `URLSessionConfiguration`
        // has no equivalent to hook one in), so `resolveExecutor()` must fall through to
        // `.nio`/`.nioTransportServices`, and `resolvedClient` must cache a `.nio` entry rather
        // than a `.urlSession` one. (A SOCKS proxy used to be this test's example, but it's no
        // longer incompatible; see `InternalsSessionConfigurationExecutorTests
        // .configuration_whenSOCKSProxySet_doesNotContainReason`.)
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()

        var sessionConfiguration = Internals.Session.Configuration()
        sessionConfiguration.dnsOverride = ["example.com": "127.0.0.1"]

        #expect(sessionConfiguration.resolveExecutor() != .urlSession)

        // When
        let resolved = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        // Then
        guard case .nio = resolved else {
            Issue.record("Expected .nio, got \(resolved)")
            return
        }
    }

    /// Regression coverage for the `enableNetworkFramework`/executor unification:
    /// `resolvedClient`'s `.nio` fallback branch used to always call
    /// `client(provider:sessionConfiguration:)` unmodified, which decides
    /// NIOTransportServices-vs-plain-NIO purely from the `enableNetworkFramework` flag, never from
    /// `resolveExecutor()`'s own (correct) answer. `preferredExecutor(.nioTransportServices)`
    /// therefore had zero effect on which event loop group backed a real client.
    ///
    /// `enableNetworkFramework` is never set here at all, proving this is `resolveExecutor()`'s
    /// decision alone, not the flag's.
    @Test
    func
        resolvedClient_whenNIOTransportServicesPreferredWithoutEnableNetworkFrameworkFlag_actuallyUsesNIOTSEventLoopGroup()
        async throws
    {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()

        var configuration = Internals.Session.Configuration()
        configuration.preferredExecutor = .nioTransportServices

        #expect(configuration.resolveExecutor() == .nioTransportServices)
        #expect(!configuration.enableNetworkFramework)

        // When
        let resolved = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: configuration
        )

        // Then
        guard case .nio(let client) = resolved else {
            Issue.record("Expected .nio, got \(resolved)")
            return
        }

        #expect(client.eventLoopGroup is NIOTSEventLoopGroup)
    }

    /// Counterpart to the test above: a config `resolveExecutor()` sends to plain `.nio` (here,
    /// pinned explicitly) must not end up on a NIOTransportServices-backed event loop group just
    /// because the configuration happens to be compatible with it.
    @Test
    func resolvedClient_whenNIORequired_doesNotUseNIOTransportServicesEventLoopGroup() async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()

        var configuration = Internals.Session.Configuration()
        configuration.requiredExecutor = .nio

        // When
        let resolved = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: configuration
        )

        // Then
        guard case .nio(let client) = resolved else {
            Issue.record("Expected .nio, got \(resolved)")
            return
        }

        #expect(!(client.eventLoopGroup is NIOTSEventLoopGroup))
    }
}

#endif
