//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct DigestAuthenticationTests {

    @Test
    func digestAuthentication_whenCredentialHasNoChallenge_setsNoHeader() async throws {
        // Given
        let credential = DigestCredential()

        let property = DigestAuthentication(
            credential,
            username: "Mufasa",
            password: "Circle of Life"
        )

        // When
        let resolved = try await resolve(TestProperty(property))

        // Then
        #expect(resolved.requestConfiguration.headers["Authorization"] == nil)
    }

    @Test
    func digestAuthentication_whenCredentialHasChallenge_setsComputedHeader() async throws {
        // Given
        let credential = DigestCredential()
        credential.challenge = try #require(
            DigestChallenge(
                headerValue:
                    #"Digest realm="http-auth@example.org", qop="auth", algorithm=SHA-256, nonce="7ypf/xlj9XXwfDPEoM4URrv/xwf94BcCAzFZH4GiTo0v", opaque="FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS""#
            )
        )

        let property = DigestAuthentication(
            credential,
            username: "Mufasa",
            password: "Circle of Life",
            method: .get
        )

        // When
        let resolved = try await resolve(
            TestProperty {
                Path("dir/index.html")
                property
            }
        )

        // Then
        let header = try #require(resolved.requestConfiguration.headers["Authorization"]?.first)
        #expect(header.hasPrefix("Digest "))
        #expect(header.contains(#"username="Mufasa""#))
        #expect(header.contains(#"realm="http-auth@example.org""#))
        #expect(header.contains(#"uri="/dir/index.html""#))
        #expect(header.contains("algorithm=SHA-256"))
        #expect(header.contains(#"opaque="FQhe/qaU925kfnzjCev0ciny7QMkPqMAFRtzCUYo5tdS""#))
        #expect(header.contains("qop=auth"))
        #expect(header.contains("nc=00000001"))
    }

    @Test
    func digestAuthentication_whenPasswordDiffers_producesADifferentResponse() async throws {
        // Given
        func header(password: String) async throws -> String {
            let credential = DigestCredential()
            credential.challenge = try #require(
                DigestChallenge(
                    headerValue: #"Digest realm="test", qop="auth", nonce="abc123", algorithm=MD5"#
                )
            )

            let resolved = try await resolve(
                TestProperty(
                    DigestAuthentication(credential, username: "user", password: password)
                )
            )

            return try #require(resolved.requestConfiguration.headers["Authorization"]?.first)
        }

        // When
        let correct = try await header(password: "right-password")
        let wrong = try await header(password: "wrong-password")

        // Then
        #expect(correct != wrong)
    }
}
