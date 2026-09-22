//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

struct InternalsProxyTests {

    /// Regression coverage for a pooled-client cache collision: `Internals.Session.Configuration
    /// .==` uses `Internals.Proxy.==` (transitively) as `Internals.ClientManager`'s pooled-client
    /// cache key. `connectHeaders` is where proxy-auth secrets distinct per session commonly
    /// live, so two proxies differing only there must compare unequal -- otherwise one session's
    /// pooled client (built with its own CONNECT headers baked in) could be silently handed to a
    /// request for a *different* session's proxy credentials, leaking one session's proxy
    /// authorization into another's traffic.
    @Test
    func proxy_whenConnectHeadersDiffer_shouldNotBeEqual() {
        // Given
        let host = UUID().uuidString
        let port = 1_090

        var connectHeaders = Internals.HTTPHeaders()
        connectHeaders.add(name: "X-Proxy-Token", value: "abc123")

        // When
        let lhs = Internals.Proxy(host: host, port: port, connection: .http, authorization: nil)
        let rhs = Internals.Proxy(
            host: host,
            port: port,
            connection: .http,
            authorization: nil,
            connectHeaders: connectHeaders
        )

        // Then
        #expect(lhs != rhs)
    }

    @Test
    func proxy_whenConnectHeadersMatch_shouldBeEqualAndHashEqual() {
        // Given
        let host = UUID().uuidString
        let port = 1_090

        var connectHeaders = Internals.HTTPHeaders()
        connectHeaders.add(name: "X-Proxy-Token", value: "abc123")

        // When
        let lhs = Internals.Proxy(
            host: host,
            port: port,
            connection: .http,
            authorization: nil,
            connectHeaders: connectHeaders
        )
        let rhs = Internals.Proxy(
            host: host,
            port: port,
            connection: .http,
            authorization: nil,
            connectHeaders: connectHeaders
        )

        // Then
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }
}

// The remaining tests all read `configuration.build().httpClientConfiguration`, and both
// `Output` (the type `build()` returns) and `.httpClientConfiguration`'s
// `HTTPClient.Configuration` (AsyncHTTPClient) only exist under `canImport(NIOCore)`.
#if canImport(NIOCore)

extension InternalsProxyTests {

    @Test
    func proxy_whenHTTPConnectionWithoutAuthorization() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let host = UUID().uuidString
        let port = 1_090

        // When
        configuration.proxy = .init(
            host: host,
            port: port,
            connection: .http,
            authorization: nil
        )

        let resolved = try configuration.build().httpClientConfiguration

        // Then
        #expect(resolved.proxy?.host == host)
        #expect(resolved.proxy?.port == port)
    }

    @Test
    func proxy_whenHTTPConnectionWithAuthorization() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let host = UUID().uuidString
        let port = 1_090
        let credentials = UUID().uuidString

        // When
        configuration.proxy = .init(
            host: host,
            port: port,
            connection: .http,
            authorization: .basicRawCredentials(credentials)
        )

        let resolved = try configuration.build().httpClientConfiguration

        // Then
        #expect(resolved.proxy?.host == host)
        #expect(resolved.proxy?.port == port)
        #expect(resolved.proxy?.authorization == .basic(credentials: credentials))
    }

    @Test
    func proxy_whenSOCKSConnectionWithoutAuthorization() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let host = UUID().uuidString
        let port = 1_090

        // When
        configuration.proxy = .init(
            host: host,
            port: port,
            connection: .socks,
            authorization: nil
        )

        let resolved = try configuration.build().httpClientConfiguration

        // Then
        #expect(resolved.proxy?.host == host)
        #expect(resolved.proxy?.port == port)
    }

    @Test
    func proxy_whenHTTPConnectionWithConnectHeaders() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let host = UUID().uuidString
        let port = 1_090

        var connectHeaders = Internals.HTTPHeaders()
        connectHeaders.add(name: "X-Proxy-Token", value: "first")
        connectHeaders.add(name: "X-Proxy-Token", value: "second")

        // When
        configuration.proxy = .init(
            host: host,
            port: port,
            connection: .http,
            authorization: nil,
            connectHeaders: connectHeaders
        )

        let resolved = try configuration.build().httpClientConfiguration

        // Then
        #expect(resolved.proxy?.connectHeaders["X-Proxy-Token"] == ["first", "second"])
    }
}

#endif
