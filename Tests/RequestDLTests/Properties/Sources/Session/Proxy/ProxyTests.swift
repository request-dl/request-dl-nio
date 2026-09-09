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
    func proxy_whenHTTPConnectionWithUsernamePasswordAuthorization() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090
        let username = UUID().uuidString
        let password = UUID().uuidString

        // When
        let resolved = try await resolve(
            Proxy(
                host: host,
                port: port,
                authorization: .basic(username: username, password: password)
            )
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
        #expect(
            resolved.session.configuration.proxy?.authorization
                == .basic(username: username, password: password)
        )
    }

    @Test
    func proxy_whenHTTPConnectionWithBearerAuthorization() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090
        let tokens = UUID().uuidString

        // When
        let resolved = try await resolve(
            Proxy(
                host: host,
                port: port,
                authorization: .bearer(tokens: tokens)
            )
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
        #expect(resolved.session.configuration.proxy?.authorization == .bearer(tokens: tokens))
    }

    @Test
    func proxy_whenHTTPConnectionWithConnectHeaders() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090
        let name = UUID().uuidString
        let value = UUID().uuidString

        // When
        let resolved = try await resolve(
            Proxy(host: host, port: port) {
                CustomHeader(name: name, value: value)
            }
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
        #expect(resolved.session.configuration.proxy?.connectHeaders.first(name: name) == value)
    }

    @Test
    func proxy_whenHTTPConnectionWithConnectHeadersFromHeaderGroup() async throws {
        // Given
        // Regression test: `HeaderGroup` used to wrap its resolved headers into an opaque leaf
        // node, invisible to `Proxy`'s `search(for: HeaderNode.self)` over its `connectHeaders`
        // content, so every header composed through it here silently disappeared.
        let host = UUID().uuidString
        let port = 1_090
        let name = UUID().uuidString
        let value = UUID().uuidString

        // When
        let resolved = try await resolve(
            Proxy(host: host, port: port) {
                HeaderGroup {
                    CustomHeader(name: name, value: value)
                }
            }
        )

        // Then
        #expect(resolved.session.configuration.proxy?.host == host)
        #expect(resolved.session.configuration.proxy?.port == port)
        #expect(resolved.session.configuration.proxy?.connectHeaders.first(name: name) == value)
    }

    @Test
    func proxy_whenHTTPConnectionWithAuthorizationAndConnectHeaders() async throws {
        // Given
        let host = UUID().uuidString
        let port = 1_090
        let credentials = UUID().uuidString
        let name = UUID().uuidString
        let value = UUID().uuidString

        // When
        let resolved = try await resolve(
            Proxy(host: host, port: port, authorization: .basic(credentials: credentials)) {
                CustomHeader(name: name, value: value)
            }
        )

        // Then
        #expect(resolved.session.configuration.proxy?.authorization == .basicRawCredentials(credentials))
        #expect(resolved.session.configuration.proxy?.connectHeaders.first(name: name) == value)
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
