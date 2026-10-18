//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Foundation
import Testing

@testable import RequestDLInternals

/// Which TLS challenges the client identity is presented to under `.urlSession`: the ones from an
/// origin a request was made to with the client, host and port, as `.nio` does.
struct InternalsURLSessionTLSDelegateTests {

    @Test
    func isConfiguredOrigin_whenHostAndPortAreARegisteredOrigins_isTrue() throws {
        // Given
        let delegate = try makeDelegate(registered: [("example.com", 443)])

        // Then
        #expect(delegate.isConfiguredOrigin(protectionSpace(host: "example.com", port: 443)))
    }

    /// A redirect to another port of the same host is another service.
    @Test
    func isConfiguredOrigin_whenOnlyThePortDiffers_isFalse() throws {
        // Given
        let delegate = try makeDelegate(registered: [("example.com", 443)])

        // Then
        #expect(!delegate.isConfiguredOrigin(protectionSpace(host: "example.com", port: 8_443)))
    }

    @Test
    func isConfiguredOrigin_whenOnlyTheHostDiffers_isFalse() throws {
        // Given
        let delegate = try makeDelegate(registered: [("example.com", 443)])

        // Then
        #expect(!delegate.isConfiguredOrigin(protectionSpace(host: "evil.example.net", port: 443)))
    }

    @Test
    func isConfiguredOrigin_ignoresTheCaseOfTheHost() throws {
        // Given
        let delegate = try makeDelegate(registered: [("example.com", 443)])

        // Then
        #expect(delegate.isConfiguredOrigin(protectionSpace(host: "Example.COM", port: 443)))
    }

    /// The same rule as `.nio`: an origin that was requested directly with this client stays
    /// eligible for as long as the client lives, so a redirect that comes back to it, from a
    /// later request to another origin, is given the identity. The caller addressed it itself.
    @Test
    func isConfiguredOrigin_whenAnEarlierRequestWasMadeToTheOrigin_isTrueForALaterDelegate() throws {
        // Given: a first request to one origin, then a second to another, with the same client.
        let origins = Internals.IdentityOrigins()
        origins.register(host: "first.example.com", port: 443)

        let later = try makeDelegate(origins: origins, registered: [("second.example.com", 443)])

        // Then
        #expect(later.isConfiguredOrigin(protectionSpace(host: "first.example.com", port: 443)))
        #expect(later.isConfiguredOrigin(protectionSpace(host: "second.example.com", port: 443)))
        #expect(!later.isConfiguredOrigin(protectionSpace(host: "third.example.com", port: 443)))
    }

    // MARK: - Helpers

    private func makeDelegate(
        origins: Internals.IdentityOrigins = .init(),
        registered: [(host: String, port: Int)]
    ) throws -> Internals.URLSessionClient.TLSDelegate {
        for origin in registered {
            origins.register(host: origin.host, port: origin.port)
        }

        return .init(
            origins: origins,
            policy: try Internals.URLSessionIdentityPolicy(Internals.SecureConnection())
        )
    }

    private func protectionSpace(host: String, port: Int) -> URLProtectionSpace {
        URLProtectionSpace(
            host: host,
            port: port,
            protocol: NSURLProtectionSpaceHTTPS,
            realm: nil,
            authenticationMethod: NSURLAuthenticationMethodClientCertificate
        )
    }
}

#endif
