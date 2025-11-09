/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
import NIOCore
import AsyncHTTPClient
@testable import RequestDL

struct InternalsSessionConfigurationTests {

    @Test
    func configuration_whenSetTLSConfiguration_shouldBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        let secureConnection = Internals.SecureConnection()

        // When
        configuration.secureConnection = secureConnection

        let builtConfiguration = try configuration.build()

        // Then
        #expect(try builtConfiguration.tlsConfiguration?.bestEffortEquals(secureConnection.build()) ?? false)
    }

    @Test
    func configuration_whenSetRedirectConfiguration_shouldBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        let redirectConfiguration = Internals.RedirectConfiguration.disallow

        // When
        configuration.redirectConfiguration = redirectConfiguration

        let builtConfiguration = try configuration.build()

        // Then
        #expect(
            String(
                describing: builtConfiguration.redirectConfiguration
            ) == String(
                describing: redirectConfiguration.build()
            )
        )
    }

    @Test
    func configuration_whenSetTimeout_shouldBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let connect = UnitTime.seconds(60)
        let read = UnitTime.seconds(60)

        let timeout = Internals.Timeout(
            connect: connect,
            read: read
        )

        // When
        configuration.timeout = timeout

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.timeout.connect == connect.build())
        #expect(builtConfiguration.timeout.read == read.build())
    }

    @Test
    func configuration_whenSetConnectionPool_shouldBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let connectionPool = HTTPClient.Configuration.ConnectionPool(idleTimeout: .seconds(16))

        // When
        configuration.connectionPool = connectionPool

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.connectionPool == connectionPool)
    }

    @Test
    func configuration_whenSetHTTPProxyWith_shoudlBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let proxy = Internals.Proxy(
            host: "localhost",
            port: 8888,
            connection: .http,
            authorization: nil
        )

        // When
        configuration.proxy = proxy

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.proxy?.host == proxy.host)
        #expect(builtConfiguration.proxy?.port == proxy.port)
        #expect(builtConfiguration.proxy?.authorization == nil)
    }

    @Test
    func configuration_whenSetHTTPProxyWithAuthorization_shoudlBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let username = UUID().uuidString
        let password = UUID().uuidString

        let proxy = Internals.Proxy(
            host: "localhost",
            port: 8888,
            connection: .http,
            authorization: .basic(username: username, password: password)
        )

        // When
        configuration.proxy = proxy

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.proxy?.host == proxy.host)
        #expect(builtConfiguration.proxy?.port == proxy.port)
        #expect(builtConfiguration.proxy?.authorization == .basic(username: username, password: password))
    }

    @Test
    func configuration_whenSetHTTPProxyWithRawAuthorization_shoudlBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let credentials = UUID().uuidString

        let proxy = Internals.Proxy(
            host: "localhost",
            port: 8888,
            connection: .http,
            authorization: .basicRawCredentials(credentials)
        )

        // When
        configuration.proxy = proxy

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.proxy?.host == proxy.host)
        #expect(builtConfiguration.proxy?.port == proxy.port)
        #expect(builtConfiguration.proxy?.authorization == .basic(credentials: credentials))
    }

    @Test
    func configuration_whenSetSOCKSProxy_shoudlBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let proxy = Internals.Proxy(
            host: "localhost",
            port: 8888,
            connection: .socks,
            authorization: nil
        )

        // When
        configuration.proxy = proxy

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.proxy?.host == proxy.host)
        #expect(builtConfiguration.proxy?.port == proxy.port)
        #expect(builtConfiguration.proxy?.authorization == nil)
    }

    @Test
    func configuration_whenSetDecompression_shouldBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let decompression = Internals.Decompression.enabled(.size(16))

        // When
        configuration.decompression = decompression

        let builtConfiguration = try configuration.build()

        // Then
        #expect(
            String(
                describing: builtConfiguration.decompression
            ) == String(
                describing: decompression.build()
            )
        )
    }

    @Test
    func configuration_whenSetHttpVersion_shouldBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()

        let version = Internals.HTTPVersion.http1Only

        // When
        configuration.httpVersion = version

        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.httpVersion == version.build())
    }

    @Test
    func configuration_whenWaitForConnectivity_shouldBeEqual() async throws {
        // Given
        var configuration = Internals.Session.Configuration()
        let waitForConnectivity = false

        // When
        configuration.networkFrameworkWaitForConnectivity = waitForConnectivity

        let builtConfiguration = try configuration.build()

        // Then
        #expect(!builtConfiguration.networkFrameworkWaitForConnectivity)
    }

    @Test
    func configuration_whenInit_shouldBeDefault() async throws {
        // When
        let configuration = Internals.Session.Configuration()
        let builtConfiguration = try configuration.build()

        // Then
        #expect(builtConfiguration.tlsConfiguration == nil)
        #expect(
            String(
                describing: builtConfiguration.redirectConfiguration
            ) == String(
                describing: HTTPClient.Configuration.RedirectConfiguration.follow(max: 5, allowCycles: false)
            )
        )
        #expect(builtConfiguration.timeout.connect == nil)
        #expect(builtConfiguration.timeout.read == nil)
        #expect(builtConfiguration.proxy == nil)
        #expect(
            String(
                describing: builtConfiguration.decompression
            ) == String(
                describing: HTTPClient.Decompression.disabled
            )
        )
        #expect(builtConfiguration.httpVersion == .automatic)
        #expect(builtConfiguration.networkFrameworkWaitForConnectivity)
    }
}
