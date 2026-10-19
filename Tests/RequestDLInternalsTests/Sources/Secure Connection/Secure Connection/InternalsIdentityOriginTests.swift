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

/// What an mTLS identity is offered to, the same on `.nio` and on `.urlSession`.
struct InternalsIdentityOriginTests {

    @Test
    func equality_isHostAndPort() {
        #expect(
            Internals.IdentityOrigin(host: "example.com", port: 443)
                == Internals.IdentityOrigin(host: "example.com", port: 443)
        )
        #expect(
            Internals.IdentityOrigin(host: "example.com", port: 443)
                != Internals.IdentityOrigin(host: "example.com", port: 8_443)
        )
        #expect(
            Internals.IdentityOrigin(host: "example.com", port: 443)
                != Internals.IdentityOrigin(host: "other.example.com", port: 443)
        )
    }

    @Test
    func init_ignoresHostCaseAndIPv6Brackets() {
        #expect(
            Internals.IdentityOrigin(host: "Example.COM", port: 443)
                == Internals.IdentityOrigin(host: "example.com", port: 443)
        )
        #expect(
            Internals.IdentityOrigin(host: "[::1]", port: 8_443)
                == Internals.IdentityOrigin(host: "::1", port: 8_443)
        )
    }

    @Test(arguments: [
        ("https://example.com/path", "example.com", 443),
        ("https://example.com:8443/path", "example.com", 8_443),
        ("HTTPS://Example.COM", "example.com", 443),
        ("http://example.com", "example.com", 80),
        ("https://[::1]:9000/", "::1", 9_000),
    ])
    func initFromURL_usesThePortOfTheSchemeWhenThereIsNone(
        _ url: String,
        _ host: String,
        _ port: Int
    ) throws {
        // When
        let parsed = try #require(URL(string: url))
        let origin = try #require(Internals.IdentityOrigin(url: parsed))

        // Then
        #expect(origin == Internals.IdentityOrigin(host: host, port: port))
    }

    @Test
    func initFromURL_withoutAHost_isNil() throws {
        let relative = try #require(URL(string: "/relative/path"))

        #expect(Internals.IdentityOrigin(url: relative) == nil)
    }
}
