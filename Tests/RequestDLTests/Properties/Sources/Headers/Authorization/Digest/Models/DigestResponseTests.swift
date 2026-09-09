//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct DigestResponseTests {

    /// The worked SHA-256 example from RFC 7616 §3.9.1. The `response` value below is the
    /// RFC's own published result -- independently cross-checked outside this codebase, feeding
    /// this same challenge/credential/`cnonce` chain through `shasum -a 256` by hand, and the two
    /// agreed byte for byte, before trusting it as this test's expectation.
    @Test
    func header_matchesRFC7616SHA256WorkedExample() throws {
        // Given
        let challenge = try #require(
            DigestChallenge(
                headerValue:
                    #"Digest realm="http-auth@example.org", qop="auth", algorithm=SHA-256, nonce="7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v""#
            )
        )

        // When
        let header = DigestResponse.header(
            for: challenge,
            username: "Mufasa",
            password: "Circle of Life",
            method: "GET",
            uri: "/dir/index.html",
            cnonce: "f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ"
        )

        // Then
        #expect(
            header.contains(#"response="753927fa0e85d155564e2e272a28d1802ca10daf4496794697cf8db5856cb6c1""#)
        )
        #expect(header.contains(#"username="Mufasa""#))
        #expect(header.contains(#"realm="http-auth@example.org""#))
        #expect(header.contains(#"nonce="7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v""#))
        #expect(header.contains(#"uri="/dir/index.html""#))
        #expect(header.contains(#"cnonce="f2/wE4q74E6zIJEtWaHKaf5wv/H5QzzpXusqGemxURZJ""#))
        #expect(header.contains("nc=00000001"))
        #expect(header.contains("qop=auth"))
        #expect(header.contains("algorithm=SHA-256"))
    }

    @Test
    func header_whenNoQop_omitsQopNcAndCnonce() throws {
        // Given
        let challenge = try #require(
            DigestChallenge(headerValue: #"Digest realm="test", nonce="abc123", algorithm=MD5"#)
        )

        // When
        let header = DigestResponse.header(
            for: challenge,
            username: "user",
            password: "pass",
            method: "GET",
            uri: "/resource"
        )

        // Then
        #expect(!header.contains("qop="))
        #expect(!header.contains("nc="))
        #expect(!header.contains("cnonce="))
    }

    @Test
    func header_whenNoOpaque_omitsOpaque() throws {
        // Given
        let challenge = try #require(
            DigestChallenge(headerValue: #"Digest realm="test", nonce="abc123""#)
        )

        // When
        let header = DigestResponse.header(
            for: challenge,
            username: "user",
            password: "pass",
            method: "GET",
            uri: "/resource"
        )

        // Then
        #expect(!header.contains("opaque="))
    }

    @Test
    func header_whenMethodDiffers_producesADifferentResponse() throws {
        // Given
        let challenge = try #require(
            DigestChallenge(headerValue: #"Digest realm="test", nonce="abc123""#)
        )

        // When
        let get = DigestResponse.header(
            for: challenge,
            username: "user",
            password: "pass",
            method: "GET",
            uri: "/resource"
        )
        let post = DigestResponse.header(
            for: challenge,
            username: "user",
            password: "pass",
            method: "POST",
            uri: "/resource"
        )

        // Then
        #expect(get != post)
    }

    @Test
    func header_generatesAFreshCnonceEachCall() throws {
        // Given
        let challenge = try #require(
            DigestChallenge(headerValue: #"Digest realm="test", qop="auth", nonce="abc123""#)
        )

        // When
        let first = DigestResponse.header(
            for: challenge,
            username: "user",
            password: "pass",
            method: "GET",
            uri: "/resource"
        )
        let second = DigestResponse.header(
            for: challenge,
            username: "user",
            password: "pass",
            method: "GET",
            uri: "/resource"
        )

        // Then
        #expect(first != second)
    }
}
