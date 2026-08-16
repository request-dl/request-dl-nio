//
// See LICENSE for this package's licensing information.
//

import NIOHTTP1
import Testing

@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

struct InternalsProxyTests {

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

        let resolved = try configuration.build()

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

        let resolved = try configuration.build()

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

        let resolved = try configuration.build()

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

        var connectHeaders = HTTPHeaders()
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

        let resolved = try configuration.build()

        // Then
        #expect(resolved.proxy?.connectHeaders["X-Proxy-Token"] == ["first", "second"])
    }

    @Test
    func proxy_whenConnectHeadersDiffer_shouldStillBeEqualAndHashEqual() {
        // Given
        let host = UUID().uuidString
        let port = 1_090

        var connectHeaders = HTTPHeaders()
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
        #expect(lhs == rhs)
        #expect(lhs.hashValue == rhs.hashValue)
    }
}
