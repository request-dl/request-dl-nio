//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import Security

/// `.socks`, mapped onto `URLSessionConfiguration.connectionProxyDictionary`'s `SOCKSEnable`/
/// `SOCKSProxy`/`SOCKSPort` keys -- the SOCKS counterpart to
/// `InternalsURLSessionClientProxyTests`, proving a full SOCKS5 handshake (`LocalSOCKSProxy`, a
/// real hand-rolled server, not just a byte-counting listener) actually carries traffic end to
/// end, not just that `URLSession` dials the configured address
/// (`InternalsSOCKSProxyDictionaryPlatformTests`'s own, narrower scope).
///
/// **Same macOS/Catalyst-only known issue as the `.http` suite, for the same reason:**
/// `LocalServer`/`LocalSOCKSProxy` always bind to `localhost`, and macOS/Catalyst bypass a
/// configured proxy for `localhost` by name as OS-level policy, independent of protocol --
/// confirmed for `.http` in `InternalsProxyDictionaryPlatformTests`, and this OS policy has no
/// reason to distinguish SOCKS from HTTP CONNECT (both are just "is this destination proxied at
/// all," decided before either protocol is spoken). iOS, tvOS, watchOS, and visionOS Simulators
/// don't bypass `localhost`, so these round trips genuinely pass there.
struct InternalsURLSessionClientSOCKSProxyTests {

    /// See the type doc comment, and `InternalsProxyDictionaryPlatformTests`'s file-level one, for
    /// why this specific pair of platforms is the one that bypasses `localhost`.
    private static var bypassesLocalhostProxying: Bool {
        #if os(macOS) || targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    @Test
    func execute_whenSOCKSProxyConfigured_tunnelsUnlessPlatformBypassesLocalhost() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello Through The SOCKS Tunnel"

        localServer.cleanup(at: uri)
        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: output), at: uri)
        defer { localServer.cleanup(at: uri) }

        let proxy = try await LocalSOCKSProxy.start()

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            proxy: Internals.Proxy(
                host: proxy.host,
                port: proxy.port,
                connection: .socks,
                authorization: nil
            )
        )

        // When
        let result = try await client.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then -- expected to fail only on macOS/Catalyst (see the type doc comment); genuinely
        // passes elsewhere, reaching the destination through a real SOCKS5 handshake and decoding
        // `output`.
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
