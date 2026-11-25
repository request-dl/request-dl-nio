//
// See LICENSE for this package's licensing information.
//

import Logging
import SwiftAsyncStream
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

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
        #expect(proxy?.authorization == .socks(username: "user", password: "secret"))
    }

    @Test
    func aSocksProxy_percentDecodesItsCredentials() throws {
        let proxy = try proxy("http://example.com", ["http_proxy": "socks5://us%40er:p%3Ass%C3%A9@socks.example"])

        #expect(proxy?.authorization == .socks(username: "us@er", password: "p:ssé"))
    }

    @Test
    func aSocksProxy_withAUserAndNoPassword_hasAnEmptyPassword() throws {
        let proxy = try proxy("http://example.com", ["http_proxy": "socks5://user@socks.example"])

        #expect(proxy?.authorization == .socks(username: "user", password: ""))
    }

    @Test
    func aSocks5hProxy_keepsItsCredentials() throws {
        let proxy = try proxy("http://example.com", ["http_proxy": "socks5h://u:p@h"])

        #expect(proxy?.connectionProtocol == .socks)
        #expect(proxy?.authorization == .socks(username: "u", password: "p"))
    }

    /// Credentials RFC 1929 cannot carry were dropped before this change (the proxy ran without
    /// them) and still are, instead of failing a request the user did not configure; and said so.
    @Test(arguments: [
        ("socks5://:p@h", "the user name is empty"),
        ("socks5://\(String(repeating: "u", count: 256)):p@h", "the user name is longer than 255 bytes"),
        ("socks5://u:\(String(repeating: "p", count: 256))@h", "the password is longer than 255 bytes"),
        ("socks5://u:p%00q@h", "the user name or the password has a NUL character"),
    ])
    func aSocksProxy_withCredentialsItCannotCarry_dropsThemAndSaysWhy(_ value: String, _ reason: String) async throws {
        let records = EnvironmentLogRecords()
        let url = try #require(URL(string: "http://example.com"))

        let proxy = await Logger.withTestHandler(recorded: records.append) { logger in
            Internals.SystemProxyResolver.proxy(forURL: url, environment: ["http_proxy": value], logger: logger)
        }

        #expect(proxy?.host == "h")
        #expect(proxy?.connectionProtocol == .socks)
        #expect(proxy?.authorization == nil)

        let recorded = records.all
        #expect(recorded.count == 1)
        #expect(recorded.first?.level == .warning)
        #expect(recorded.first?.metadata["reason"] == .string(reason))
        // Why, never the credentials.
        let text = recorded.map(\.description).joined()
        #expect(!text.contains("uuuu") && !text.contains("pppp") && !text.contains(":p@"))
    }

    /// Credentials that are written but do not percent-decode used to become an empty password
    /// (and the empty password was then sent to the proxy) or vanish without a word. They are
    /// dropped as a whole, and said so.
    @Test(arguments: [
        "socks5://user:p%FFss@h",
        "socks5://us%FFer:pass@h",
    ])
    func aSocksProxy_withCredentialsThatDoNotPercentDecode_dropsThemAndSaysWhy(_ value: String) async throws {
        let records = EnvironmentLogRecords()
        let url = try #require(URL(string: "http://example.com"))

        let proxy = await Logger.withTestHandler(recorded: records.append) { logger in
            Internals.SystemProxyResolver.proxy(forURL: url, environment: ["http_proxy": value], logger: logger)
        }

        #expect(proxy?.host == "h")
        #expect(proxy?.connectionProtocol == .socks)
        #expect(proxy?.authorization == nil)

        let recorded = records.all
        #expect(recorded.count == 1)
        #expect(recorded.first?.level == .warning)
        #expect(
            recorded.first?.metadata["reason"]
                == .string("the user name or the password is not valid percent-encoded text")
        )
        let text = recorded.map(\.description).joined()
        #expect(!text.contains("%FF") && !text.contains("user:") && !text.contains("pass@"))
    }

    @Test
    func aSocksProxy_withCredentialsItCarries_logsNothing() async throws {
        let records = EnvironmentLogRecords()
        let url = try #require(URL(string: "http://example.com"))

        await Logger.withTestHandler(recorded: records.append) { logger in
            _ = Internals.SystemProxyResolver.proxy(
                forURL: url,
                environment: ["http_proxy": "socks5://u:p@h"],
                logger: logger
            )
        }

        #expect(records.all.isEmpty)
    }

    @Test
    func anHTTPProxy_withEmptyUser_isLeftAlone() throws {
        // The drop is for SOCKS only: an HTTP proxy never validated its credentials.
        let proxy = try proxy("http://example.com", ["http_proxy": "http://:p@h"])

        #expect(proxy?.authorization == .basic(username: "", password: "p"))
    }

    @Test
    func aSocksProxy_withoutAUser_hasNoCredentials() throws {
        let proxy = try proxy("http://example.com", ["http_proxy": "socks5://socks.example"])

        #expect(proxy?.authorization == nil)
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

private final class EnvironmentLogRecords: @unchecked Sendable {

    private let lock = Lock()
    private var records: [TestLogHandler.LogRecord] = []

    var all: [TestLogHandler.LogRecord] {
        lock.withLock { records }
    }

    var append: @Sendable (TestLogHandler.LogRecord) -> Void {
        { record in self.lock.withLock { self.records.append(record) } }
    }
}
