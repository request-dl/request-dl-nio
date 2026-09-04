//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct DigestChallengeTests {

    @Test
    func init_whenFullChallengeWithQop_parsesEveryField() throws {
        // Given
        let header =
            #"Digest realm="http-auth@example.org", qop="auth", algorithm=SHA-256, nonce="abc123", opaque="xyz789""#

        // When
        let challenge = try #require(DigestChallenge(headerValue: header))

        // Then
        #expect(challenge.realm == "http-auth@example.org")
        #expect(challenge.nonce == "abc123")
        #expect(challenge.opaque == "xyz789")
        #expect(challenge.algorithm == .sha256)
        #expect(challenge.hasAuthQop)
    }

    @Test
    func init_whenNoAlgorithm_defaultsToMD5() throws {
        // Given
        let header = #"Digest realm="test", nonce="abc123""#

        // When
        let challenge = try #require(DigestChallenge(headerValue: header))

        // Then
        #expect(challenge.algorithm == .md5)
        #expect(!challenge.hasAuthQop)
        #expect(challenge.opaque == nil)
    }

    @Test
    func init_whenQopOffersAuthAndAuthInt_recognizesAuth() throws {
        // Given -- a comma-separated qop list inside quotes, per RFC 7616 §3.3.
        let header = #"Digest realm="test", qop="auth,auth-int", nonce="abc123""#

        // When
        let challenge = try #require(DigestChallenge(headerValue: header))

        // Then
        #expect(challenge.hasAuthQop)
    }

    @Test
    func init_whenQopOnlyOffersAuthInt_doesNotRecognizeAuth() throws {
        // Given
        let header = #"Digest realm="test", qop="auth-int", nonce="abc123""#

        // When
        let challenge = try #require(DigestChallenge(headerValue: header))

        // Then
        #expect(!challenge.hasAuthQop)
    }

    @Test
    func init_whenMissingRealm_isNil() {
        #expect(DigestChallenge(headerValue: #"Digest nonce="abc123""#) == nil)
    }

    @Test
    func init_whenMissingNonce_isNil() {
        #expect(DigestChallenge(headerValue: #"Digest realm="test""#) == nil)
    }

    @Test
    func init_whenNotDigestScheme_isNil() {
        #expect(DigestChallenge(headerValue: #"Basic realm="test""#) == nil)
    }

    @Test
    func init_whenUnsupportedAlgorithm_isNil() {
        #expect(DigestChallenge(headerValue: #"Digest realm="test", nonce="abc123", algorithm=SHA-512"#) == nil)
    }

    @Test
    func init_whenSessionAlgorithm_isNil() {
        #expect(DigestChallenge(headerValue: #"Digest realm="test", nonce="abc123", algorithm=MD5-sess"#) == nil)
    }

    @Test
    func init_isCaseInsensitiveOnScheme() throws {
        let challenge = try #require(DigestChallenge(headerValue: #"digest realm="test", nonce="abc123""#))
        #expect(challenge.realm == "test")
    }

    @Test
    func init_toleratesACommaInsideAQuotedValue() throws {
        // Given -- a comma inside `opaque`, which RFC 7616 does not forbid.
        let header = #"Digest realm="test", nonce="abc123", opaque="left,right""#

        // When
        let challenge = try #require(DigestChallenge(headerValue: header))

        // Then
        #expect(challenge.opaque == "left,right")
    }
}
