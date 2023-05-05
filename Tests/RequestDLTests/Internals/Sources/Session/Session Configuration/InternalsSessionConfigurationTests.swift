/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOCore
import AsyncHTTPClient
@testable import RequestDL

@RequestActor
class InternalsSessionConfigurationTests: XCTestCase {

    var configuration: Internals.Session.Configuration!

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
        let secureConnection = Internals.SecureConnection()

        // When
        configuration.secureConnection = secureConnection

        let configuration = try configuration.build()

        // Then
        XCTAssertTrue(try configuration.tlsConfiguration?.bestEffortEquals(secureConnection.build()) ?? false)
    }

    func testConfiguration_whenSetRedirectConfiguration_shouldBeEqual() async throws {
        // Given
        let redirectConfiguration = Internals.RedirectConfiguration.disallow

        // When
        configuration.redirectConfiguration = redirectConfiguration

        let configuration = try configuration.build()

        // Then
        XCTAssertEqual(
            String(describing: configuration.redirectConfiguration),
            String(describing: redirectConfiguration.build())
        )
    }

    func testConfiguration_whenSetTimeout_shouldBeEqual() async throws {
        // Given
        let connect = UnitTime.seconds(60)
        let read = UnitTime.seconds(60)

        let timeout = Internals.Timeout(
            connect: connect,
            read: read
        )

        // When
        configuration.timeout = timeout

        let configuration = try configuration.build()

        // Then
        XCTAssertEqual(configuration.timeout.connect, connect.build())
        XCTAssertEqual(configuration.timeout.read, read.build())
    }

    func testConfiguration_whenSetConnectionPool_shouldBeEqual() async throws {
        // Given
        let connectionPool = HTTPClient.Configuration.ConnectionPool(idleTimeout: .seconds(16))

        // When
        configuration.connectionPool = connectionPool

        let configuration = try configuration.build()

        // Then
        XCTAssertEqual(configuration.connectionPool, connectionPool)
    }

    func testConfiguration_whenSetProxy_shoudlBeEqual() async throws {
        // Given
        let proxy = HTTPClient.Configuration.Proxy.server(
            host: "localhost",
            port: 8888
        )

        // When
        configuration.proxy = proxy

        let configuration = try configuration.build()

        // Then
        XCTAssertEqual(configuration.proxy, proxy)
    }

    func testConfiguration_whenSetDecompression_shouldBeEqual() async throws {
        // Given
        let decompression = Internals.Decompression.enabled(.size(16))

        // When
        configuration.decompression = decompression

        let configuration = try configuration.build()

        // Then
        XCTAssertEqual(
            String(describing: configuration.decompression),
            String(describing: decompression.build())
        )
    }

    func testConfiguration_whenSetHttpVersion_shouldBeEqual() async throws {
        // Given
        let version = Internals.HTTPVersion.http1Only

        // When
        configuration.httpVersion = version

        let configuration = try configuration.build()

        // Then
        XCTAssertEqual(configuration.httpVersion, version.build())
    }

    func testConfiguration_whenWaitForConnectivity_shouldBeEqual() async throws {
        // Given
        let waitForConnectivity = false

        // When
        configuration.networkFrameworkWaitForConnectivity = waitForConnectivity

        let configuration = try configuration.build()

        // Then
        XCTAssertFalse(configuration.networkFrameworkWaitForConnectivity)
    }

    func testConfiguration_whenInit_shouldBeDefault() async throws {
        // When
        let configuration = try configuration.build()

        // Then
        XCTAssertNil(configuration.tlsConfiguration)
        XCTAssertEqual(
            String(describing: configuration.redirectConfiguration),
            String(describing: HTTPClient.Configuration.RedirectConfiguration.follow(max: 5, allowCycles: false))
        )
        XCTAssertNil(configuration.timeout.connect)
        XCTAssertNil(configuration.timeout.read)
        XCTAssertNil(configuration.proxy)
        XCTAssertEqual(
            String(describing: configuration.decompression),
            String(describing: HTTPClient.Decompression.disabled)
        )
        XCTAssertEqual(configuration.httpVersion, .automatic)
        XCTAssertTrue(configuration.networkFrameworkWaitForConnectivity)
    }
}
