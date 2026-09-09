//
// See LICENSE for this package's licensing information.
//

import NIOCore
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import NIOTransportServices

/// `Internals.ClientManager.resolvedClient(provider:sessionConfiguration:)` actually selects and
/// caches an `Internals.URLSessionClient` for a configuration `resolveExecutor()` picks
/// `.urlSession` for, rather than that decision staying abstract. Distinct from
/// `RequestConfigurationURLSessionClientTests` (`RequestDLTests`), which
/// forces `.urlSession` by hand-building `Internals.URLSessionClient` directly and bypasses
/// `Internals.ClientManager` entirely -- these tests are the ones that would fail if
/// `resolvedClient` merely inspected `resolveExecutor()` without ever building/caching a real
/// client behind it.
struct InternalsClientManagerExecutorTests {

    @Test
    func resolvedClient_whenConfigurationHasNoExecutorPreference_actuallyRunsOverURLSession() async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: .seconds(5 * 60))
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Internals.Session.Configuration()

        // `resolveExecutor()` alone only says what *could* run -- the point of this suite is
        // confirming `resolvedClient` actually built and cached the client that decision points
        // to, not just returned a matching enum case with nothing behind it.
        #expect(sessionConfiguration.resolveExecutor() == .urlSession)

        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))

        // When
        let resolved = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        // Then
        guard case .urlSession(let client) = resolved else {
            Issue.record("Expected .urlSession, got \(resolved)")
            return
        }

        let result = try await client.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )

        let decoded = try JSONDecoder().decode(HTTPResult<String>.self, from: result.body)
        #expect(result.head.status.code == 200)
        #expect(decoded.response == output)
    }

    @Test
    func resolvedClient_whenCalledTwice_reusesTheSameURLSessionClient() async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: .seconds(5 * 60))
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Internals.Session.Configuration()

        // When
        let first = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        let second = try await manager.resolvedClient(
            provider: provider,
            sessionConfiguration: sessionConfiguration
        )

        // Then
        guard
            case .urlSession(let firstClient) = first,
            case .urlSession(let secondClient) = second
        else {
            Issue.record("Expected both resolutions to be .urlSession")
            return
        }

        #expect(firstClient === secondClient)
    }

    @Test
    func resolvedClient_whenConfigurationIsIncompatibleWithURLSession_fallsBackToNIO() async throws {
        // Given -- a DNS override is excluded from `.urlSession` (bucket D; `URLSessionConfiguration`
        // has no equivalent to hook one in), so `resolveExecutor()` must fall through to
        // `.nio`/`.nioTransportServices`, and `resolvedClient` must cache a `.nio` entry rather
        // than a `.urlSession` one. (A SOCKS proxy used to be this test's example -- no longer
        // incompatible, see `InternalsSessionConfigurationExecutorTests
        // .configuration_whenSOCKSProxySet_doesNotContainReason`.)
        let manager = Internals.ClientManager(lifetime: .seconds(5 * 60))
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

    /// Regression coverage for the `enableNetworkFramework`/executor unification --
    /// `resolvedClient`'s `.nio` fallback branch used to always call
    /// `client(provider:sessionConfiguration:)` unmodified, which decides
    /// NIOTransportServices-vs-plain-NIO purely from the `enableNetworkFramework` flag, never from
    /// `resolveExecutor()`'s own (correct) answer. `preferredExecutor(.nioTransportServices)`
    /// therefore had zero effect on which event loop group backed a real client.
    /// `enableNetworkFramework` is never set here at all -- proving this is `resolveExecutor()`'s
    /// decision alone, not the flag's.
    @Test
    func
        resolvedClient_whenNIOTransportServicesPreferredWithoutEnableNetworkFrameworkFlag_actuallyUsesNIOTSEventLoopGroup()
        async throws
    {
        // Given
        let manager = Internals.ClientManager(lifetime: .seconds(5 * 60))
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
        let manager = Internals.ClientManager(lifetime: .seconds(5 * 60))
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

/// Test-only stand-in for the real TLS challenge handling -- see the identical delegate in
/// `InternalsURLSessionClientTests`/`RequestConfigurationURLSessionClientTests` for why this
/// exists at all: `LocalServer` is always TLS-terminated with a throwaway self-signed
/// certificate.
private final class AcceptAnyServerTrustDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

#endif
