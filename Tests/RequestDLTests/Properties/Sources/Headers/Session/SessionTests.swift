/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import AsyncHTTPClient
@testable import RequestDL

@RequestActor
class SessionTests: XCTestCase {

    func testSession_whenInitAsDefault_shouldBeValid() async throws {
        // Given
        let property = Session()
        let configuration = Internals.Session.Configuration()

        // When
        let (session, _) = try await resolve(TestProperty { property })
        let sut = session.configuration

        // Then
        XCTAssertEqual(sut.connectionPool, configuration.connectionPool)
        XCTAssertNil(sut.redirectConfiguration)
        XCTAssertEqual(sut.timeout.connect, configuration.timeout.connect)
        XCTAssertEqual(sut.timeout.read, configuration.timeout.read)
        XCTAssertEqual(sut.proxy, configuration.proxy)
        XCTAssertEqual(sut.ignoreUncleanSSLShutdown, configuration.ignoreUncleanSSLShutdown)
        XCTAssertEqual(
            String(describing: sut.decompression),
            String(describing: configuration.decompression)
        )
        XCTAssertEqual(sut.connectionPool, configuration.connectionPool)
    }

    func testSession_whenInitWithIdentifier_shouldBeValid() async throws {
        // Given
        let property = Session("other", numberOfThreads: 10)

        // When
        let sut = property.provider

        // Then
        XCTAssertEqual(sut.id, "other.10")
    }

    func testSession_whenWaitsForConnectivity_shouldBeValid() async throws {
        // Given
        let waitsForConnectivity = true

        let property = Session()
            .waitsForConnectivity(waitsForConnectivity)

        // When
        let (session, _) = try await resolve(TestProperty { property })

        // Then
        XCTAssertEqual(try session.configuration.build().networkFrameworkWaitForConnectivity, waitsForConnectivity)
    }

    func testSession_whenMaxConnectionsPerHost_shouldBeValid() async throws {
        // Given
        let maximumConnections = 10

        let property = Session()
            .maximumConnectionsPerHost(maximumConnections)

        // When
        let (session, _) = try await resolve(TestProperty { property })

        // Then
        XCTAssertEqual(
            session.configuration.connectionPool.concurrentHTTP1ConnectionsPerHostSoftLimit,
            maximumConnections
        )
    }

    func testSession_whenDisableRedirect_shouldBeValid() async throws {
        // Given
        let property = Session()
            .disableRedirect()

        // When
        let (session, _) = try await resolve(TestProperty { property })

        // Then
        guard let redirectConfiguration = session.configuration.redirectConfiguration else {
            XCTFail("Redirect Configuration is nil")
            return
        }

        XCTAssertEqual(
            redirectConfiguration,
            .disallow
        )
    }

    func testSession_whenEnableRedirect_shouldBeValid() async throws {
        // Given
        let max = 1_000
        let cycles = true

        let property = Session()
            .enableRedirectFollow(max: max, allowCycles: cycles)

        // When
        let (session, _) = try await resolve(TestProperty { property })

        // Then
        guard let redirectConfiguration = session.configuration.redirectConfiguration else {
            XCTFail("Redirect Configuration is nil")
            return
        }

        XCTAssertEqual(
            redirectConfiguration,
            .follow(
                max: max,
                allowCycles: cycles
            )
        )
    }

    func testSession_whenIgnoreUncleanSSLShutdown_shouldBeValid() async throws {
        // Given
        let property = Session()
            .ignoreUncleanSSLShutdown()

        // When
        let (session, _) = try await resolve(TestProperty { property })

        // Then
        XCTAssertTrue(session.configuration.ignoreUncleanSSLShutdown)
    }

    func testSession_whenDecompressionDisabled_shouldBeValid() async throws {
        // Given
        let property = Session()
            .disableDecompression()

        // When
        let (session, _) = try await resolve(TestProperty { property })

        // Then
        XCTAssertEqual(
            String(describing: session.configuration.decompression),
            String(describing: HTTPClient.Decompression.disabled)
        )
    }

    func testSession_whenDecompressionLimit_shouldBeValid() async throws {
        // Given
        let decompressionLimit = Session.DecompressionLimit.ratio(5_000)
        let property = Session()
            .decompressionLimit(decompressionLimit)

        // When
        let (session, _) = try await resolve(TestProperty { property })

        // Then
        XCTAssertEqual(
            session.configuration.decompression,
            .enabled(decompressionLimit.build())
        )
    }

    func testSession_whenDNSOverride_shouldBeValid() async throws {
        // Given
        let origin = "google.com"
        let destination = "apple.com"

        let property = Session()
            .overrideDNS(destination, from: origin)

        // When
        let (session, _) = try await resolve(TestProperty { property })

        // Then
        XCTAssertEqual(
            try session.configuration.build().dnsOverride,
            [origin: destination]
        )
    }

    func testSession_whenNeverBody_shouldBeNever() async throws {
        // Given
        let property = Session()

        // Then
        try await assertNever(property.body)
    }

    func testSession_whenCollidesPrefersLastDeclared() async throws {
        // Given
        let property = TestProperty {
            Session()
                .decompressionLimit(.size(200))
            Session()
                .waitsForConnectivity(true)
        }

        // When
        let (session, _) = try await resolve(property)

        // Then
        XCTAssertEqual(session.configuration.decompression, .enabled(.size(200)))
        XCTAssertEqual(session.configuration.networkFrameworkWaitForConnectivity, true)
    }
}
