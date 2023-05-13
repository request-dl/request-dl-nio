/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class TimeoutTests: XCTestCase {

    func testRequestTimeout() async throws {
        // Given
        let requestTimeout = Timeout.Source.connect
        let timeout = UnitTime.seconds(75)

        // When
        let resolved = try await resolve(TestProperty {
            Timeout(timeout, for: requestTimeout)
        })

        // Then
        XCTAssertEqual(resolved.session.configuration.timeout.connect, timeout)
    }

    func testResourceTimeout() async throws {
        // Given
        let resourceTimeout = Timeout.Source.connect
        let timeout = UnitTime.seconds(1_999)

        // When
        let resolved = try await resolve(TestProperty(Timeout(timeout, for: resourceTimeout)))

        // Then
        XCTAssertEqual(resolved.session.configuration.timeout.connect, timeout)
    }

    func testAllTimeout() async throws {
        // Given
        let requestTimeout = Timeout.Source.all
        let timeout = UnitTime.seconds(75)

        // When
        let resolved = try await resolve(TestProperty(Timeout(timeout, for: requestTimeout)))

        // Then
        XCTAssertEqual(resolved.session.configuration.timeout.read, timeout)
        XCTAssertEqual(resolved.session.configuration.timeout.connect, timeout)
    }

    func testDefaultTimeout() async throws {
        let defaultConfiguration = Internals.Session.Configuration()

        // When
        let resolved = try await resolve(TestProperty {})

        // Then
        XCTAssertEqual(
            resolved.session.configuration.timeout.read,
            defaultConfiguration.timeout.read
        )

        XCTAssertEqual(
            resolved.session.configuration.timeout.connect,
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
