//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(Darwin) && canImport(CFNetwork)

import CFNetwork
import Foundation

/// `Internals.SystemProxyResolver.firstResolution(in:)`/`firstUsableProxy(in:)` against synthetic
/// CFNetwork proxy-list dictionaries -- the same shape `CFNetworkCopyProxiesForURL` and a PAC
/// script's own evaluated result both use, exercised directly here instead of through either of
/// those (both depend on state -- system settings, or a real script fetch -- this suite doesn't
/// control).
struct InternalsSystemProxyResolverTests {

    @Test
    func firstResolution_whenEmpty_isNil() async throws {
        // Given / When
        let resolution = Internals.SystemProxyResolver.firstResolution(in: [])

        // Then
        #expect(resolution == nil)
    }

    @Test
    func firstResolution_whenNoneEntry_isDirect() async throws {
        // Given
        let proxies = [[kCFProxyTypeKey as String: kCFProxyTypeNone]]

        // When
        let resolution = Internals.SystemProxyResolver.firstResolution(in: proxies)

        // Then
        #expect(resolution == .direct)
    }

    @Test
    func firstResolution_whenNoneEntryPrecedesAnHTTPEntry_stopsAtDirect() async throws {
        // Given -- later entries are fallbacks for a failed proxy, not alternatives to try
        // instead of an explicit direct connection.
        let proxies: [[String: Any]] = [
            [kCFProxyTypeKey as String: kCFProxyTypeNone],
            [
                kCFProxyTypeKey as String: kCFProxyTypeHTTP,
                kCFProxyHostNameKey as String: "127.0.0.1",
                kCFProxyPortNumberKey as String: 8_080,
            ],
        ]

        // When
        let resolution = Internals.SystemProxyResolver.firstResolution(in: proxies)

        // Then
        #expect(resolution == .direct)
    }

    @Test(arguments: [kCFProxyTypeHTTP as String, kCFProxyTypeHTTPS as String])
    func firstResolution_whenHTTPOrHTTPSEntry_resolvesHTTPProxy(_ type: String) async throws {
        // Given
        let proxies: [[String: Any]] = [
            [
                kCFProxyTypeKey as String: type,
                kCFProxyHostNameKey as String: "proxy.example.com",
                kCFProxyPortNumberKey as String: 3_128,
            ]
        ]

        // When
        let resolution = Internals.SystemProxyResolver.firstResolution(in: proxies)

        // Then
        guard case .proxy(let proxy) = resolution else {
            Issue.record("Expected .proxy, got \(String(describing: resolution))")
            return
        }
        #expect(proxy.host == "proxy.example.com")
        #expect(proxy.port == 3_128)
        #expect(proxy.connectionProtocol == .http)
    }

    @Test
    func firstResolution_whenSOCKSEntry_resolvesSOCKSProxy() async throws {
        // Given
        let proxies: [[String: Any]] = [
            [
                kCFProxyTypeKey as String: kCFProxyTypeSOCKS,
                kCFProxyHostNameKey as String: "127.0.0.1",
                kCFProxyPortNumberKey as String: 1_080,
            ]
        ]

        // When
        let resolution = Internals.SystemProxyResolver.firstResolution(in: proxies)

        // Then
        guard case .proxy(let proxy) = resolution else {
            Issue.record("Expected .proxy, got \(String(describing: resolution))")
            return
        }
        #expect(proxy.port == 1_080)
        #expect(proxy.connectionProtocol == .socks)
    }

    @Test
    func firstResolution_whenEntryCarriesCredentials_includesBasicAuthorization() async throws {
        // Given
        let proxies: [[String: Any]] = [
            [
                kCFProxyTypeKey as String: kCFProxyTypeHTTP,
                kCFProxyHostNameKey as String: "proxy.example.com",
                kCFProxyPortNumberKey as String: 8_080,
                kCFProxyUsernameKey as String: "user",
                kCFProxyPasswordKey as String: "pass",
            ]
        ]

        // When
        let resolution = Internals.SystemProxyResolver.firstResolution(in: proxies)

        // Then
        guard case .proxy(let proxy) = resolution else {
            Issue.record("Expected .proxy, got \(String(describing: resolution))")
            return
        }
        #expect(proxy.authorization == .basic(username: "user", password: "pass"))
    }

    @Test
    func firstResolution_whenEntryMissingHostOrPort_skipsToNextEntry() async throws {
        // Given -- an HTTP entry missing its port is unusable and skipped, falling through to
        // the SOCKS entry after it.
        let proxies: [[String: Any]] = [
            [
                kCFProxyTypeKey as String: kCFProxyTypeHTTP,
                kCFProxyHostNameKey as String: "proxy.example.com",
            ],
            [
                kCFProxyTypeKey as String: kCFProxyTypeSOCKS,
                kCFProxyHostNameKey as String: "127.0.0.1",
                kCFProxyPortNumberKey as String: 1_080,
            ],
        ]

        // When
        let resolution = Internals.SystemProxyResolver.firstResolution(in: proxies)

        // Then
        guard case .proxy(let proxy) = resolution else {
            Issue.record("Expected .proxy, got \(String(describing: resolution))")
            return
        }
        #expect(proxy.connectionProtocol == .socks)
    }

    @Test
    func firstResolution_whenAutoConfigurationURLEntry_surfacesTheScriptURL() async throws {
        // Given
        let scriptURL = try #require(URL(string: "https://example.com/proxy.pac"))
        let proxies: [[String: Any]] = [
            [
                kCFProxyTypeKey as String: kCFProxyTypeAutoConfigurationURL,
                kCFProxyAutoConfigurationURLKey as String: scriptURL,
            ]
        ]

        // When
        let resolution = Internals.SystemProxyResolver.firstResolution(in: proxies)

        // Then
        #expect(resolution == .autoConfiguration(scriptURL))
    }

    @Test
    func firstUsableProxy_whenAutoConfigurationURLEntry_isNil() async throws {
        // Given -- `firstUsableProxy(in:)` is `Internals.PACEvaluator`'s own entry point, parsing
        // an *already evaluated* PAC result, which CFNetwork guarantees never itself contains an
        // auto-configuration entry. Defensively treated the same as "nothing this package
        // recognizes" rather than recursing.
        let scriptURL = try #require(URL(string: "https://example.com/proxy.pac"))
        let proxies: [[String: Any]] = [
            [
                kCFProxyTypeKey as String: kCFProxyTypeAutoConfigurationURL,
                kCFProxyAutoConfigurationURLKey as String: scriptURL,
            ]
        ]

        // When / Then
        #expect(Internals.SystemProxyResolver.firstUsableProxy(in: proxies) == nil)
    }

    @Test
    func firstUsableProxy_whenDirect_isNil() async throws {
        // Given / When / Then
        #expect(
            Internals.SystemProxyResolver.firstUsableProxy(
                in: [[kCFProxyTypeKey as String: kCFProxyTypeNone]]
            ) == nil
        )
    }

    @Test
    func firstUsableProxy_whenProxyEntry_returnsIt() async throws {
        // Given
        let proxies: [[String: Any]] = [
            [
                kCFProxyTypeKey as String: kCFProxyTypeHTTP,
                kCFProxyHostNameKey as String: "proxy.example.com",
                kCFProxyPortNumberKey as String: 8_080,
            ]
        ]

        // When
        let proxy = Internals.SystemProxyResolver.firstUsableProxy(in: proxies)

        // Then
        #expect(proxy?.host == "proxy.example.com")
    }
}

#endif
