/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOCore
import AsyncHTTPClient
@testable import RequestDL

class InternalsSessionConfigurationTests: XCTestCase {

    var configuration: Internals.Session.Configuration?

    override func setUp() async throws {
        try await super.setUp()
        configuration = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        configuration = nil
    }

    func testConfiguration_whenSetTLSConfiguration_shouldBeEqual() async throws {
        // Given
        var configuration = try XCTUnwrap(configuration)
        let secureConnection = Internals.SecureConnection()

        // When
        configuration.secureConnection = secureConnection

        let builtConfiguration = try configuration.build()

        // Then
        XCTAssertTrue(try builtConfiguration.tlsConfiguration?.bestEffortEquals(secureConnection.build()) ?? false)
    }

    func testConfiguration_whenSetRedirectConfiguration_shouldBeEqual() async throws {
        // Given
        var configuration = try XCTUnwrap(configuration)
        let redirectConfiguration = Internals.RedirectConfiguration.disallow

        // When
        configuration.redirectConfiguration = redirectConfiguration

        let builtConfiguration = try configuration.build()

        // Then
        XCTAssertEqual(
            String(describing: builtConfiguration.redirectConfiguration),
            String(describing: redirectConfiguration.build())
        )
    }

    func testConfiguration_whenSetTimeout_shouldBeEqual() async throws {
        // Given
        var configuration = try XCTUnwrap(configuration)

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
        XCTAssertEqual(builtConfiguration.timeout.connect, connect.build())
        XCTAssertEqual(builtConfiguration.timeout.read, read.build())
    }

    func testConfiguration_whenSetConnectionPool_shouldBeEqual() async throws {
        // Given
        var configuration = try XCTUnwrap(configuration)

        let connectionPool = HTTPClient.Configuration.ConnectionPool(idleTimeout: .seconds(16))

        // When
        configuration.connectionPool = connectionPool

        let builtConfiguration = try configuration.build()

        // Then
        XCTAssertEqual(builtConfiguration.connectionPool, connectionPool)
    }

    func testConfiguration_whenSetProxy_shoudlBeEqual() async throws {
        // Given
        var configuration = try XCTUnwrap(configuration)

        let proxy = HTTPClient.Configuration.Proxy.server(
            host: "localhost",
            port: 8888
        )

        // When
        configuration.proxy = proxy

        let builtConfiguration = try configuration.build()

        // Then
        XCTAssertEqual(builtConfiguration.proxy, proxy)
    }

    func testConfiguration_whenSetDecompression_shouldBeEqual() async throws {
        // Given
        var configuration = try XCTUnwrap(configuration)

        let decompression = Internals.Decompression.enabled(.size(16))

        // When
        configuration.decompression = decompression

        let builtConfiguration = try configuration.build()

        // Then
        XCTAssertEqual(
            String(describing: builtConfiguration.decompression),
            String(describing: decompression.build())
        )
    }

    func testConfiguration_whenSetHttpVersion_shouldBeEqual() async throws {
        // Given
        var configuration = try XCTUnwrap(configuration)

        let version = Internals.HTTPVersion.http1Only

        // When
        configuration.httpVersion = version

        let builtConfiguration = try configuration.build()

        // Then
        XCTAssertEqual(builtConfiguration.httpVersion, version.build())
    }

    func testConfiguration_whenWaitForConnectivity_shouldBeEqual() async throws {
        // Given
        var configuration = try XCTUnwrap(configuration)
        let waitForConnectivity = false

        // When
        configuration.networkFrameworkWaitForConnectivity = waitForConnectivity

        let builtConfiguration = try configuration.build()

        // Then
        XCTAssertFalse(builtConfiguration.networkFrameworkWaitForConnectivity)
    }

    func testConfiguration_whenInit_shouldBeDefault() async throws {
        // When
        var configuration = try XCTUnwrap(configuration)
        let builtConfiguration = try configuration.build()

        // Then
        XCTAssertNil(builtConfiguration.tlsConfiguration)
        XCTAssertEqual(
            String(describing: builtConfiguration.redirectConfiguration),
            String(describing: HTTPClient.Configuration.RedirectConfiguration.follow(max: 5, allowCycles: false))
        )
        XCTAssertNil(builtConfiguration.timeout.connect)
        XCTAssertNil(builtConfiguration.timeout.read)
        XCTAssertNil(builtConfiguration.proxy)
        XCTAssertEqual(
            String(describing: builtConfiguration.decompression),
            String(describing: HTTPClient.Decompression.disabled)
        )
        XCTAssertEqual(builtConfiguration.httpVersion, .automatic)
        XCTAssertTrue(builtConfiguration.networkFrameworkWaitForConnectivity)
    }
}
