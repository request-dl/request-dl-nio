//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct URLOverrideEndpointTests {

    private func endpoint(_ url: String) throws -> URLOverrideEndpoint {
        try URLOverrideEndpoint(parsing: url)
    }

    @Test(arguments: [
        ("https://example.com", "https://example.com:443"),
        ("http://example.com", "http://example.com:80"),
        ("wss://example.com", "wss://example.com:443"),
        ("ws://example.com", "ws://example.com:80"),
        ("HTTPS://EXAMPLE.com", "https://example.com"),
        ("https://example.com:8443", "https://Example.com:8443"),
    ])
    func isSameOrigin_whenTheyNameTheSameOrigin(_ lhs: String, _ rhs: String) throws {
        #expect(try endpoint(lhs).isSameOrigin(as: endpoint(rhs)))
        #expect(try endpoint(rhs).isSameOrigin(as: endpoint(lhs)))
    }

    @Test(arguments: [
        ("https://example.com", "https://example.com:8443"),
        ("https://example.com", "http://example.com"),
        ("http://example.com", "http://example.com:443"),
        ("https://example.com", "https://www.example.com"),
        ("https://example.com", "https://example.com:80"),
    ])
    func isSameOrigin_whenTheyDoNot(_ lhs: String, _ rhs: String) throws {
        #expect(try !endpoint(lhs).isSameOrigin(as: endpoint(rhs)))
        #expect(try !endpoint(rhs).isSameOrigin(as: endpoint(lhs)))
    }

    /// A scheme with no default port: a missing port is not any port in particular.
    @Test
    func isSameOrigin_forASchemeWithNoDefaultPort_needsTheSamePortOrNone() throws {
        #expect(try endpoint("custom://example.com").isSameOrigin(as: endpoint("custom://example.com")))
        #expect(try !endpoint("custom://example.com").isSameOrigin(as: endpoint("custom://example.com:443")))
    }

    /// A rule is parsed from a user string and the request's origin from the base URL the
    /// properties built, and they must agree on an IPv6 host whichever way each spells it.
    @Test
    func isSameOrigin_forAnIPv6Host_agreesBetweenARuleAndARequest() throws {
        let rule = try endpoint("https://[::1]")
        let request = try #require(URLOverrideEndpoint(baseURL: "https://[::1]"))
        let withPort = try #require(URLOverrideEndpoint(baseURL: "https://[::1]:443"))

        #expect(rule.isSameOrigin(as: request))
        #expect(rule.isSameOrigin(as: withPort))
    }

    // MARK: - Percent-encoded delimiters in the host

    /// `URLComponents.host` is percent-decoded: an `%23`, `%2F`, `%3F` or `%40` in the host of a
    /// rule would end up as a real delimiter in the base URL it rewrites a request to.
    @Test(arguments: [
        "https://attacker.com%23.good.com/v1",
        "https://attacker.com%2F.good.com/v1",
        "https://attacker.com%3F.good.com/v1",
        "https://attacker.com%40good.com/v1",
        "https://attacker.com%5C.good.com/v1",
        "https://attacker.com%20.good.com/v1",
        "https://attacker.com%2523.good.com/v1",
        "https://127.0.0.1%3A6379/v1",
    ])
    func parsing_anEncodedDelimiterInTheHost_throws(_ url: String) {
        let error = #expect(throws: URLOverrideError.self) {
            try URLOverrideEndpoint(parsing: url)
        }

        #expect(error?.context == .invalidURL)
        #expect(error?.url == url)
    }

    @Test(arguments: [
        ("https://example.com:8443/a", "example.com", 8443),
        ("https://[::1]:8443/a", "[::1]", 8443),
    ])
    func parsing_aLegitimateHost_isAccepted(_ url: String, _ host: String, _ port: Int?) throws {
        let parsed = try endpoint(url)

        #expect(parsed.host.lowercased() == host)
        #expect(parsed.port == port)
    }
}
