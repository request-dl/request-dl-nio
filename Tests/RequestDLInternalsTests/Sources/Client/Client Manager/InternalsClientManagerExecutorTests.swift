//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation

/// `Internals.ClientManager.resolvedClient(provider:sessionConfiguration:)` actually selects and
/// caches an `Internals.URLSessionClient` for a configuration `resolveExecutor()` picks
/// `.urlSession` for, rather than that decision staying abstract.
///
/// Distinct from `RequestConfigurationURLSessionClientTests` (`RequestDLTests`), which
/// forces `.urlSession` by hand-building `Internals.URLSessionClient` directly and bypasses
/// `Internals.ClientManager` entirely: these tests are the ones that would fail if
/// `resolvedClient` merely inspected `resolveExecutor()` without ever building/caching a real
/// client behind it.
///
/// Only the `.urlSession` half of the suite: none of these tests reference `.nio` or
/// `NIOTransportServices`, so they need nothing beyond `canImport(Darwin)` and keep compiling
/// under `--disable-default-traits`. The `.nio`/`.nioTransportServices` half lives in
/// `InternalsClientManagerExecutorTests+NIO.swift`, which needs `NIOCore` to exist at all.
struct InternalsClientManagerExecutorTests {

    @Test
    func resolvedClient_whenConfigurationHasNoExecutorPreference_actuallyRunsOverURLSession() async throws {
        // Given
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
        let provider = Internals.SharedSessionProvider()
        let sessionConfiguration = Internals.Session.Configuration()

        // `resolveExecutor()` alone only says what *could* run. The point of this suite is
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
        let manager = Internals.ClientManager(lifetime: 5 * 60 * 1_000_000_000)
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
}

/// Test-only stand-in for the real TLS challenge handling; see the identical delegate in
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
