/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOCore
import AsyncHTTPClient
@testable import RequestDLInternals

class ConfigurationTests: XCTestCase {

    var configuration: Session.Configuration!

    override func setUp() async throws {
        try await super.setUp()
        configuration = .init()
    }

    override func tearDown() async throws {
        try await super.tearDown()
        configuration = nil
    }

    func testConfiguration_whenSetTLSConfiguration_shoudlBeEqual() async throws {
        // Given
        let tlsConfiguration = Session.TLSConfiguration.clientDefault

        // When
        configuration.tlsConfiguration = tlsConfiguration

        let configuration = configuration.build()

        // Then
        XCTAssertEqual(configuration.tlsConfiguration, tlsConfiguration)
    }

    func testConfiguration_whenSetRedirectConfiguration_shoudlBeEqual() async throws {
        // Given
        let redirectConfiguration = HTTPClient.Configuration.RedirectConfiguration.disallow

        // When
        configuration.redirectConfiguration = redirectConfiguration

        let configuration = configuration.build()

        // Then
        XCTAssertEqual(configuration.redirectConfiguration, redirectConfiguration)
    }

    func testConfiguration_whenSetTimeout_shoudlBeEqual() async throws {
        // Given
        let connect = TimeAmount.seconds(60)
        let read = TimeAmount.seconds(60)

        let timeout = HTTPClient.Configuration.Timeout(
            connect: connect,
            read: read
        )

        // When
        configuration.timeout = timeout

        let configuration = configuration.build()

        // Then
        XCTAssertEqual(configuration.timeout.connect, connect)
        XCTAssertEqual(configuration.timeout.read, read)
    }

    func testConfiguration_whenSetConnectionPool_shoudlBeEqual() async throws {
        // Given
        let connectionPool = HTTPClient.Configuration.ConnectionPool(idleTimeout: .seconds(16))

        // When
        configuration.connectionPool = connectionPool

        let configuration = configuration.build()

        // Then
        XCTAssertEqual(configuration.connectionPool, connectionPool)
    }

    func testConfiguration_whenSetProxy_shoudlBeEqual() async throws {
        // Given
        let proxy = HTTPClient.Configuration.Proxy.server(host: "localhost", port: 8080)

        // When
        configuration.proxy = proxy

        let configuration = configuration.build()

        // Then
        XCTAssertEqual(configuration.proxy, proxy)
    }

    func testConfiguration_whenSetDecompression_shoudlBeEqual() async throws {
        // Given
        let decompression = HTTPClient.Decompression.enabled(limit: .size(16))

        // When
        configuration.decompression = decompression

        let configuration = configuration.build()

        // Then
        XCTAssertEqual(configuration.decompression, decompression)
    }

    func testConfiguration_whenSetReadingMode_shoudlBeEqual() async throws {
        // Given
        let readingMode = Response.ReadingMode.separator([70])

        // When
        configuration.readingMode = readingMode

        // Then
        XCTAssertEqual(configuration.readingMode, readingMode)
    }

    func testConfiguration_whenSetHttpVersion_shoudlBeEqual() async throws {
        // Given
        let version = HTTPClient.Configuration.HTTPVersion.http1Only

        // When
        configuration.setValue(version, forKey: \.httpVersion)

        let configuration = configuration.build()

        // Then
        XCTAssertEqual(configuration.httpVersion, version)
    }

    func testConfiguration_whenWaitForConnectivity_shouldBeEqual() async throws {
        // Given
        let waitForConnectivity = false

        // When
        configuration.setValue(waitForConnectivity, forKey: \.networkFrameworkWaitForConnectivity)

        let configuration = configuration.build()

        // Then
        XCTAssertFalse(configuration.networkFrameworkWaitForConnectivity)
    }

    func testConfiguration_whenInit_shouldBeDefault() async throws {
        // When
        let configuration = configuration.build()

        // Then
        XCTAssertNil(configuration.tlsConfiguration)
        XCTAssertEqual(configuration.redirectConfiguration, .follow(max: 5, allowCycles: false))
        XCTAssertNil(configuration.timeout.connect)
        XCTAssertNil(configuration.timeout.read)
        XCTAssertNil(configuration.proxy)
        XCTAssertEqual(configuration.decompression, .disabled)
        XCTAssertEqual(configuration.httpVersion, .automatic)
        XCTAssertTrue(configuration.networkFrameworkWaitForConnectivity)
        XCTAssertEqual(self.configuration.readingMode, .length(1_024))
    }
}