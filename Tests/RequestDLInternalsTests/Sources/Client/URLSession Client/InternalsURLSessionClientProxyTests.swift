//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import Security

/// `.http` (`.server`) `CONNECT` proxying, mapped onto
/// `URLSessionConfiguration.connectionProxyDictionary`, with `.basic`/`.basicRawCredentials`
/// proxy authentication answered through the proxy authentication challenge delegate callback.
///
/// **This suite's round trips only fail to pass on macOS and Mac Catalyst, for a reason unrelated
/// to whether the mapping is correct:** `LocalServer`/`LocalHTTPConnectProxy` always bind to
/// `localhost`, and macOS/Catalyst specifically bypass a configured proxy for `localhost` (by
/// name) as OS-level policy -- confirmed directly, and precisely, in
/// `InternalsProxyDictionaryPlatformTests`, which is where the actual mapping-correctness proof
/// and the full per-platform matrix live, not here. iOS, tvOS, watchOS, and visionOS Simulators
/// do **not** bypass `localhost`, so these round trips genuinely pass there -- `withKnownIssue`
/// below is conditioned on platform (`when:`) to match, rather than unconditionally expecting
/// failure. If `LocalServer` ever stops being loopback-only, or Apple ever changes the
/// macOS/Catalyst policy, these would need revisiting, not the mapping itself.
///
/// There was no pre-existing NIO-backend proxy round-trip suite to reuse -- `ProxyTests` and
/// `InternalsProxyTests` only cover config mapping, never an actual proxied connection -- so
/// `LocalHTTPConnectProxy` exists specifically to make this checkable at all, for either executor.
struct InternalsURLSessionClientProxyTests {

    /// See the type doc comment, and `InternalsProxyDictionaryPlatformTests`'s file-level one,
    /// for why this specific pair of platforms is the one that bypasses `localhost`.
    private static var bypassesLocalhostProxying: Bool {
        #if os(macOS) || targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    @Test
    func execute_whenProxyConfiguredWithoutAuthorization_tunnelsUnlessPlatformBypassesLocalhost() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello Through The Tunnel"

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: output), at: uri)
        defer { localServer.cleanup(at: uri) }

        let proxy = try await LocalHTTPConnectProxy.start()

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            proxy: Internals.Proxy(
                host: proxy.host,
                port: proxy.port,
                connection: .http,
                authorization: nil
            )
        )

        // When
        let result = try await client.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then -- expected to fail only on macOS/Catalyst (see the type doc comment); genuinely
        // passes elsewhere, reaching the destination and decoding `output`.
        try withKnownIssue(
            "macOS/Catalyst bypass a configured proxy for localhost -- see the type doc comment",
            {
                #expect(proxy.connectAttempts.count >= 1)

                let decoded = try JSONDecoder().decode(HTTPResult<String>.self, from: result.body)
                #expect(decoded.response == output)
            },
            when: { Self.bypassesLocalhostProxying }
        )

        try await proxy.shutdown()
    }

    @Test
    func execute_whenProxyConfiguredWithBasicAuthorization_tunnelsUnlessPlatformBypassesLocalhost() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Authenticated Tunnel"

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: output), at: uri)
        defer { localServer.cleanup(at: uri) }

        let username = "proxy-user"
        let password = "proxy-pass"
        let expectedHeaderValue = "Basic " + Data("\(username):\(password)".utf8).base64EncodedString()

        let proxy = try await LocalHTTPConnectProxy.start(requiredProxyAuthorization: expectedHeaderValue)

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            proxy: Internals.Proxy(
                host: proxy.host,
                port: proxy.port,
                connection: .http,
                authorization: .basic(username: username, password: password)
            )
        )

        // When
        let result = try await client.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then -- expected to fail only on macOS/Catalyst (see the type doc comment); genuinely
        // passes elsewhere, reaching the destination and decoding `output`.
        try withKnownIssue(
            "macOS/Catalyst bypass a configured proxy for localhost -- see the type doc comment",
            {
                #expect(proxy.connectAttempts.count >= 1)

                let decoded = try JSONDecoder().decode(HTTPResult<String>.self, from: result.body)
                #expect(decoded.response == output)
            },
            when: { Self.bypassesLocalhostProxying }
        )

        try await proxy.shutdown()
    }
}

/// Test-only stand-in for the real client's own TLS challenge handling -- see the identical
/// delegate in the other `Internals.URLSessionClient` test files for why this exists at all:
/// `LocalServer` is always TLS-terminated with a throwaway self-signed certificate.
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
