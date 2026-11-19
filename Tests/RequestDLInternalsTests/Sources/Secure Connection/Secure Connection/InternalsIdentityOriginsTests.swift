//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import AsyncHTTPClient
import Testing

#if canImport(Security)
import Security
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

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

    /// On Network.framework with a proxy, every connection is proxied and its TLS is done by
    /// NIOSSL, so the NIOSSL provider is what must answer, and the Network.framework identity,
    /// which nothing would use, is not built.
    @Test
    func build_whenProxiedOnNetworkFramework_offersTheNIOSSLIdentityAndBuildsNoNetworkFrameworkOne() throws {
        // Given
        let client = Certificates().client()

        var configuration = Internals.Session.Configuration()
        configuration.proxy = Internals.Proxy(
            host: "proxy.example.com",
            port: 8_080,
            connection: .http,
            authorization: nil
        )

        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .file(client.certificateURL.absolutePath(percentEncoded: false))
        secureConnection.privateKey = .privateKey(
            .init(client.privateKeyURL.absolutePath(percentEncoded: false), format: .pem)
        )
        configuration.secureConnection = secureConnection

        // When
        let output = try configuration.build(isCompatibleWithNetworkFramework: true)
        let httpClientConfiguration = output.httpClientConfiguration
        let provider = try #require(httpClientConfiguration.tlsLocalIdentityProviderNIOSSL)

        // Then
        output.identityOrigins.register(host: "localhost", port: 8_443)
        #expect(provider("localhost", 8_443) != nil)
        #expect(provider("redirect-target.example", 8_443) == nil)

        #if canImport(Darwin)
        #expect(output.localIdentityHandle == nil)
        #expect(httpClientConfiguration.tlsLocalIdentityProviderNetworkFramework == nil)
        #expect(httpClientConfiguration.tlsLocalIdentityChainProviderNetworkFramework == nil)
        #endif
    }

    #if canImport(Darwin)
    /// The Network.framework provider answers the identity together with its intermediates, and
    /// only for origins requests were made to: the same scoping as the NIOSSL one, with the chain
    /// AsyncHTTPClient hands to `sec_identity_create_with_certificates`.
    @Test
    func build_whenTheChainHasIntermediates_offersTheNetworkFrameworkIdentityWithThemOnlyToRegisteredOrigins()
        throws
    {
        // Given
        let leaf = CertificateResource("client_chain_leaf", format: .pem)
        let intermediate = CertificateResource("client_chain_intermediate", format: .pem)

        var configuration = Internals.Session.Configuration()
        var secureConnection = Internals.SecureConnection()
        secureConnection.certificateChain = .certificates([
            Internals.Certificate(leaf.certificateURL.absolutePath(percentEncoded: false), format: .pem),
            Internals.Certificate(intermediate.certificateURL.absolutePath(percentEncoded: false), format: .pem),
        ])
        secureConnection.privateKey = .privateKey(
            .init(leaf.privateKeyURL.absolutePath(percentEncoded: false), format: .pem)
        )
        configuration.secureConnection = secureConnection

        // When
        let output = try configuration.build(isCompatibleWithNetworkFramework: true)
        let httpClientConfiguration = output.httpClientConfiguration
        let provider = try #require(httpClientConfiguration.tlsLocalIdentityChainProviderNetworkFramework)
        let handle = try #require(output.localIdentityHandle)

        // Then: given to no origin until one is requested, and never through the leaf-only provider.
        #expect(httpClientConfiguration.tlsLocalIdentityProviderNetworkFramework == nil)
        #expect(provider("localhost", 8_443) == nil)

        output.identityOrigins.register(host: "localhost", port: 8_443)

        let identity = try #require(provider("localhost", 8_443))
        #expect(!identity.certificates.isEmpty)
        #expect(identity.certificates.count == 1)
        #expect(identity.identity === handle.identity)
        #expect(
            identity.certificates.map { SecCertificateCopyData($0) as Data }
                == Array(try #require(secureConnection.certificateChain).resolvedDERBytes().dropFirst())
        )
        #expect(provider("localhost", 9_443) == nil)
        #expect(provider("redirect-target.example", 8_443) == nil)
    }

    @Test
    func build_whenTheChainIsTheLeafAlone_offersTheNetworkFrameworkIdentityWithNoIntermediates() throws {
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
        let output = try configuration.build(isCompatibleWithNetworkFramework: true)
        let provider = try #require(output.httpClientConfiguration.tlsLocalIdentityChainProviderNetworkFramework)
        output.identityOrigins.register(host: "localhost", port: 8_443)

        // Then
        #expect(try #require(provider("localhost", 8_443)).certificates.isEmpty)
    }
    #endif

    @Test
    func build_whenNoMTLSConfigured_installsNoProvider() throws {
        // When
        let output = try Internals.Session.Configuration().build(isCompatibleWithNetworkFramework: false)

        // Then
        #expect(output.httpClientConfiguration.tlsLocalIdentityProviderNIOSSL == nil)
    }
}

#endif
