//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Foundation
import Testing

@testable import RequestDLInternals

/// Which TLS challenges the client identity is presented to under `.urlSession`: the ones from
/// the origin the request was made to, host and port, as `.nio` does.
struct InternalsURLSessionTLSDelegateTests {

    @Test
    func isConfiguredOrigin_whenHostAndPortAreTheRequests_isTrue() throws {
        // Given
        let delegate = try makeDelegate(host: "example.com", port: 443)

        // Then
        #expect(delegate.isConfiguredOrigin(protectionSpace(host: "example.com", port: 443)))
    }

    /// A redirect to another port of the same host is another service.
    @Test
    func isConfiguredOrigin_whenOnlyThePortDiffers_isFalse() throws {
        // Given
        let delegate = try makeDelegate(host: "example.com", port: 443)

        // Then
        #expect(!delegate.isConfiguredOrigin(protectionSpace(host: "example.com", port: 8_443)))
    }

    @Test
    func isConfiguredOrigin_whenOnlyTheHostDiffers_isFalse() throws {
        // Given
        let delegate = try makeDelegate(host: "example.com", port: 443)

        // Then
        #expect(!delegate.isConfiguredOrigin(protectionSpace(host: "evil.example.net", port: 443)))
    }

    @Test
    func isConfiguredOrigin_ignoresTheCaseOfTheHost() throws {
        // Given
        let delegate = try makeDelegate(host: "example.com", port: 443)

        // Then
        #expect(delegate.isConfiguredOrigin(protectionSpace(host: "Example.COM", port: 443)))
    }

    // MARK: - Helpers

    private func makeDelegate(
        host: String,
        port: Int
    ) throws -> Internals.URLSessionClient.TLSDelegate {
        .init(
            origin: .init(host: host, port: port),
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
