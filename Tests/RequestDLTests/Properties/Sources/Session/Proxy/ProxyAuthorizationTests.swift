//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

struct ProxyAuthorizationTests {

    @Test
    func standaloneUsage_notPinnedToAnyHeadersSpecialization() async throws {
        // Given
        // `ProxyAuthorization` is a top-level type, not nested inside the generic
        // `Proxy<Headers>`. A standalone helper returning it (unlike the old
        // `Proxy<SomeSpecificHeaders>.Authorization`) never forces a `Headers` specialization
        // on its own — the regression this type exists to fix.
        func makeAuthorization(credentials: String) -> ProxyAuthorization {
            .basic(credentials: credentials)
        }

        let credentials = UUID().uuidString
        let host = UUID().uuidString
        let port = 1_090

        // When
        let resolved = try await resolve(
            Proxy(host: host, port: port, authorization: makeAuthorization(credentials: credentials))
        )

        // Then
        #expect(resolved.session.configuration.proxy?.authorization == .basicRawCredentials(credentials))
    }

    @Test
    func deprecatedProxyAuthorizationAliasStillResolves() async throws {
        // Given
        // Source compatibility: `Proxy.Authorization` is a deprecated `typealias` to
        // `ProxyAuthorization`, so old call sites spelling it out explicitly still compile.
        let credentials = UUID().uuidString
        let deprecatedSpelling: Proxy<EmptyProperty>.Authorization = .basic(credentials: credentials)

        // When
        let resolved = try await resolve(
            Proxy(host: "proxy.example.com", port: 8080, authorization: deprecatedSpelling)
        )

        // Then
        #expect(resolved.session.configuration.proxy?.authorization == .basicRawCredentials(credentials))
    }
}
