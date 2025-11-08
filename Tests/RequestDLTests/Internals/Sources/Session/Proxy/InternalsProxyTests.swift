/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

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
}
