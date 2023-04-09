/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class TimeoutTests: XCTestCase {

    func testRequestTimeout() async throws {
        // Given
        let requestTimeout = Timeout.Source.connect
        let timeout = UnitTime.seconds(75)

        // When
        let (session, _) = try await resolve(TestProperty {
            Timeout(timeout, for: requestTimeout)
        })

        // Then
        XCTAssertEqual(session.configuration.timeout.connect, timeout.build())
    }

    func testResourceTimeout() async throws {
        // Given
        let resourceTimeout = Timeout.Source.connect
        let timeout = UnitTime.seconds(1_999)

        // When
        let (session, _) = try await resolve(TestProperty(Timeout(timeout, for: resourceTimeout)))

        // Then
        XCTAssertEqual(session.configuration.timeout.connect, timeout.build())
    }

    func testAllTimeout() async throws {
        // Given
        let requestTimeout = Timeout.Source.all
        let timeout = UnitTime.seconds(75)

        // When
        let (session, _) = try await resolve(TestProperty(Timeout(timeout, for: requestTimeout)))

        // Then
        XCTAssertEqual(session.configuration.timeout.read, timeout.build())
        XCTAssertEqual(session.configuration.timeout.connect, timeout.build())
    }

    func testDefaultTimeout() async throws {
        let defaultConfiguration = RequestDLInternals.Session.Configuration()

        // When
        let (session, _) = try await resolve(TestProperty {})

        // Then
        XCTAssertEqual(
            session.configuration.timeout.read,
            defaultConfiguration.timeout.read
        )

        XCTAssertEqual(
            session.configuration.timeout.connect,
            defaultConfiguration.timeout.connect
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = Timeout(.seconds(1))

        // Then
        try await assertNever(property.body)
    }
}
