/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct ProxyTests {

    @Test
    func proxy_whenHTTPConnectionWithoutAuthorization() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090

        // When
        let resolved = try await resolve(
            Proxy(
                host: host,
                port: port,
                connection: .http
            )
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
    }

    @Test
    func proxy_whenHTTPConnectionWithAuthorization() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090
        let credentials = UUID().uuidString

        // When
        let resolved = try await resolve(
            Proxy(
                host: host,
                port: port,
                authorization: .basic(credentials: credentials)
            )
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
        #expect(resolved.session.configuration.proxy?.authorization == .basicRawCredentials(credentials))
    }

    @Test
    func proxy_whenSOCKSConnectionWithoutAuthorization() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090

        // When
        let resolved = try await resolve(
            Proxy(
                host: host,
                port: port,
                connection: .socks
            )
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = Proxy(
            host: UUID().uuidString,
            port: 1_000,
            connection: .http
        )

        // Then
        try await assertNever(property.body)
    }
}
