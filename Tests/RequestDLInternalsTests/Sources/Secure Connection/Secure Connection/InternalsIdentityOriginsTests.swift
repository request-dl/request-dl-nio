//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import AsyncHTTPClient
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

struct InternalsIdentityOriginsTests {

    @Test
    func contains_whenNothingWasRegistered_isFalse() {
        #expect(!Internals.IdentityOrigins().contains(host: "example.com", port: 443))
    }

    @Test
    func contains_whenTheOriginWasRegistered_isTrue() {
        // Given
        let origins = Internals.IdentityOrigins()

        // When
        origins.register(host: "example.com", port: 443)

        // Then
        #expect(origins.contains(host: "example.com", port: 443))
    }

    /// The port is part of an origin: a redirect to another port of the same host is another
    /// origin.
    @Test
    func contains_whenOnlyThePortOrTheHostDiffers_isFalse() {
        // Given
        let origins = Internals.IdentityOrigins()
        origins.register(host: "example.com", port: 443)

        // Then
        #expect(!origins.contains(host: "example.com", port: 8_443))
        #expect(!origins.contains(host: "other.example.com", port: 443))
    }

    @Test
    func contains_ignoresHostCaseAndIPv6Brackets() {
        // Given
        let origins = Internals.IdentityOrigins()
        origins.register(host: "Example.COM", port: 443)
        origins.register(host: "[::1]", port: 8_443)

        // Then
        #expect(origins.contains(host: "example.com", port: 443))
        #expect(origins.contains(host: "::1", port: 8_443))
    }

    // MARK: - What the providers answer

    /// `build()` does not put the client identity on the client-wide `TLSConfiguration`, which
    /// AsyncHTTPClient presents to every host it connects to. It hands it to a provider that
    /// answers only for origins requests were made to.
    @Test
    func build_whenMTLSConfigured_offersTheNIOSSLIdentityOnlyToRegisteredOrigins() throws {
        // Given
        let client = Certificates().client()

        var configuration = Internals.Session.Configuration()
        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .file(client.certificateURL.absolutePath(percentEncoded: false))
        secureConnection.privateKey = .privateKey(
            .init(client.privateKeyURL.absolutePath(percentEncoded: false), format: .pem)
        )
        configuration.secureConnection = secureConnection

        // When
        let output = try configuration.build(isCompatibleWithNetworkFramework: false)
        let httpClientConfiguration = output.httpClientConfiguration
        let provider = try #require(httpClientConfiguration.tlsLocalIdentityProviderNIOSSL)

        // Then: off the configuration as a whole, and given to no origin until one is requested.
        #expect(httpClientConfiguration.tlsConfiguration?.certificateChain.isEmpty != false)
        #expect(httpClientConfiguration.tlsConfiguration?.privateKey == nil)
        #expect(provider("localhost", 8_443) == nil)

        output.identityOrigins.register(host: "localhost", port: 8_443)

        #expect(provider("localhost", 8_443) != nil)
        #expect(provider("localhost", 9_443) == nil)
        #expect(provider("redirect-target.example", 8_443) == nil)
    }

    @Test
    func build_whenNoMTLSConfigured_installsNoProvider() throws {
        // When
        let output = try Internals.Session.Configuration().build(isCompatibleWithNetworkFramework: false)

        // Then
        #expect(output.httpClientConfiguration.tlsLocalIdentityProviderNIOSSL == nil)
    }
}

#endif
