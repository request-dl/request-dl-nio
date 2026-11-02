//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

/// The proxy the environment variables name, which is what the platforms without CFNetwork treat
/// as the system proxy.
struct InternalsSystemProxyResolverEnvironmentTests {

    private func proxy(
        _ url: String,
        _ environment: [String: String]
    ) throws -> Internals.Proxy? {
        Internals.SystemProxyResolver.proxy(forURL: try #require(URL(string: url)), environment: environment)
    }

    // MARK: - Which variable

    @Test
    func http_usesHttpProxy() throws {
        let proxy = try proxy("http://example.com", ["http_proxy": "http://proxy.example:3128"])

        #expect(proxy?.host == "proxy.example")
        #expect(proxy?.port == 3_128)
    }

    @Test
    func https_usesHttpsProxy() throws {
        let proxy = try proxy(
            "https://example.com",
            ["http_proxy": "http://plain.example:1", "https_proxy": "http://secure.example:2"]
        )

        #expect(proxy?.host == "secure.example")
    }

    @Test(arguments: ["http_proxy", "HTTP_PROXY"])
    func https_neverFallsBackToTheHttpProxy(_ name: String) throws {
        #expect(try proxy("https://example.com", [name: "http://plain.example:1"]) == nil)
    }

    @Test
    func http_usesTheUpperCaseVariableOutsideCGI() throws {
        #expect(try proxy("http://example.com", ["HTTP_PROXY": "http://proxy.example:1"])?.host == "proxy.example")
    }

    @Test
    func http_ignoresTheUpperCaseVariableWhenARequestMethodIsSet() throws {
        let environment = ["HTTP_PROXY": "http://attacker.example:1", "REQUEST_METHOD": "GET"]

        #expect(try proxy("http://example.com", environment) == nil)
    }

    @Test
    func http_keepsTheLowerCaseVariableWhenARequestMethodIsSet() throws {
        let environment = ["http_proxy": "http://proxy.example:1", "REQUEST_METHOD": "GET"]

        #expect(try proxy("http://example.com", environment)?.host == "proxy.example")
    }

    @Test
    func aSocksProxy_keepsItsCredentialsAndDefaultPort() throws {
        let proxy = try proxy("http://example.com", ["http_proxy": "socks5://user:secret@socks.example"])

        #expect(proxy?.connectionProtocol == .socks)
        #expect(proxy?.port == 1_080)
        #expect(proxy?.authorization == .basic(username: "user", password: "secret"))
    }

    // MARK: - no_proxy

    private static let proxied = ["http_proxy": "http://proxy.example:1"]

    private func isProxied(_ url: String, noProxy: String) throws -> Bool {
        var environment = Self.proxied
        environment["no_proxy"] = noProxy

        return try proxy(url, environment) != nil
    }

    @Test(arguments: [
        ("http://example.com", "example.com"),
        ("http://www.example.com", "example.com"),
        ("http://www.example.com", ".example.com"),
        ("http://www.example.com", "*.example.com"),
        ("http://example.com", "other.org, EXAMPLE.com"),
        ("http://anything.org", "*"),
    ])
    func noProxy_namesAndSuffixes_skipTheProxy(_ url: String, _ noProxy: String) throws {
        #expect(try !isProxied(url, noProxy: noProxy))
    }

    @Test(arguments: [
        ("http://notexample.com", "example.com"),
        ("http://example.org", "example.com"),
        ("http://example.com", ""),
    ])
    func noProxy_otherHosts_keepTheProxy(_ url: String, _ noProxy: String) throws {
        #expect(try isProxied(url, noProxy: noProxy))
    }

    @Test
    func noProxy_withAPort_skipsOnlyThatPort() throws {
        #expect(try !isProxied("http://example.com:8080", noProxy: "example.com:8080"))
        #expect(try isProxied("http://example.com:9090", noProxy: "example.com:8080"))
        #expect(try isProxied("http://example.com", noProxy: "example.com:8080"))
        #expect(try !isProxied("http://example.com", noProxy: "example.com:80"))
        #expect(try !isProxied("https://example.com", noProxy: "example.com:443"))
    }

    @Test(arguments: [
        ("http://10.1.2.3", "10.0.0.0/8", false),
        ("http://10.255.255.255", "10.0.0.0/8", false),
        ("http://11.0.0.1", "10.0.0.0/8", true),
        ("http://192.168.1.77", "192.168.1.0/24", false),
        ("http://192.168.2.1", "192.168.1.0/24", true),
        ("http://192.168.1.130", "192.168.1.128/25", false),
        ("http://192.168.1.5", "192.168.1.128/25", true),
        ("http://10.1.2.3", "10.1.2.3/32", false),
        ("http://10.1.2.4", "10.1.2.3/32", true),
        ("http://8.8.8.8", "0.0.0.0/0", false),
        ("http://example.com", "10.0.0.0/8", true),
        ("http://10.1.2.3", "10.0.0.0/33", true),
        ("http://10.1.2.3", "10.0.0.0/abc", true),
    ])
    func noProxy_cidrRanges(_ url: String, _ noProxy: String, _ expectedProxied: Bool) throws {
        #expect(try isProxied(url, noProxy: noProxy) == expectedProxied)
    }

    @Test(arguments: [
        ("http://[2001:db8::1]/", "2001:db8::/32", false),
        ("http://[2001:db9::1]/", "2001:db8::/32", true),
        ("http://[::1]/", "::1/128", false),
        ("http://[::1]/", "::/0", false),
        ("http://[fe80::1]/", "fe80::/10", false),
        ("http://10.1.2.3", "2001:db8::/32", true),
    ])
    func noProxy_ipv6CidrRanges(_ url: String, _ noProxy: String, _ expectedProxied: Bool) throws {
        #expect(try isProxied(url, noProxy: noProxy) == expectedProxied)
    }

    @Test
    func noProxy_readsTheUpperCaseVariable() throws {
        let environment = ["http_proxy": "http://proxy.example:1", "NO_PROXY": "example.com"]

        #expect(try proxy("http://example.com", environment) == nil)
    }

    // MARK: - Edge cases

    @Test
    func aURLWithoutAHost_isDirect() throws {
        #expect(try proxy("file:///tmp/a", Self.proxied) == nil)
    }

    @Test(arguments: ["not a url", "http://", ""])
    func aProxyValueWithoutAHost_isDirect(_ value: String) throws {
        #expect(try proxy("http://example.com", ["http_proxy": value]) == nil)
    }

    @Test
    func anHttpProxyWithoutAPort_defaultsTo8080() throws {
        #expect(try proxy("http://example.com", ["http_proxy": "http://proxy.example"])?.port == 8_080)
    }

    @Test
    func aProxyWithAUserAndNoPassword_hasNoAuthorization() throws {
        let proxy = try proxy("http://example.com", ["http_proxy": "http://user@proxy.example:1"])

        #expect(proxy?.authorization == nil)
    }

    @Test(arguments: [
        ("ws://example.com", "example.com:80", false),
        ("wss://example.com", "example.com:443", false),
        ("ws://example.com", "example.com:443", true),
        ("ftp://example.com", "example.com:21", true),
        ("ftp://example.com", "example.com", false),
    ])
    func noProxy_withAPort_usesTheDefaultPortOfTheScheme(
        _ url: String,
        _ noProxy: String,
        _ expectedProxied: Bool
    ) throws {
        #expect(try isProxied(url, noProxy: noProxy) == expectedProxied)
    }

    @Test(arguments: [
        ("http://[::1]:8080/", "[::1]:8080", false),
        ("http://[::1]:9090/", "[::1]:8080", true),
        ("http://[::1]/", "[::1]", false),
        ("http://[::1]/", "::1", false),
        ("http://example.com", "example.com:abc", true),
        ("http://example.com", "other.org,, ,", true),
        ("http://example.com", "other.org,,example.com", false),
    ])
    func noProxy_entryForms(_ url: String, _ noProxy: String, _ expectedProxied: Bool) throws {
        #expect(try isProxied(url, noProxy: noProxy) == expectedProxied)
    }

    @Test(arguments: [
        "300.1.1.1/8",
        "1.2.3/8",
        "1.2.3.4.5/8",
        "a.b.c.d/8",
        "1..3.4/8",
        "10.0.0.0/-1",
        "10.0.0.0/",
        "1::2::3/64",
        "g::1/64",
        "12345::/16",
        "1:2:3:4:5:6:7::8/64",
        "1:2:3/16",
        "1:2:3:4:5:6:7:8:9/64",
        ":::/0",
        "[::1/64",
    ])
    func noProxy_invalidRanges_neverSkipTheProxy(_ noProxy: String) throws {
        #expect(try isProxied("http://10.1.2.3", noProxy: noProxy))
        #expect(try isProxied("http://[::1]/", noProxy: noProxy))
    }

    @Test(arguments: [
        ("http://[2001:db8::1]/", "2001:db8:0:0:0:0:0:0/32", false),
        ("http://[2001:db8::1]/", "2001:db8:0:0:0:0:0:1/128", false),
        ("http://[2001:db8::2]/", "2001:db8:0:0:0:0:0:1/128", true),
        ("http://[::]/", "::/128", false),
        ("http://[0:0:0:0:0:0:0:1]/", "::1/128", false),
    ])
    func noProxy_ipv6WrittenInFull(_ url: String, _ noProxy: String, _ expectedProxied: Bool) throws {
        #expect(try isProxied(url, noProxy: noProxy) == expectedProxied)
    }
}
