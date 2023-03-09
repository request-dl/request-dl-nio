/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class TimeoutTests: XCTestCase {

    func testRequestTimeout() async {
        // Given
        let requestTimeout = Timeout.Source.request
        let timeout = TimeInterval(75)

        // When
        let (session, _) = await resolve(TestProperty(Timeout(timeout, for: requestTimeout)))

        // Then
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, timeout)
    }

    func testResourceTimeout() async {
        // Given
        let resourceTimeout = Timeout.Source.resource
        let timeout = TimeInterval(1_999)

        // When
        let (session, _) = await resolve(TestProperty(Timeout(timeout, for: resourceTimeout)))

        // Then
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, timeout)
    }

    func testAllTimeout() async {
        // Given
        let requestTimeout = Timeout.Source.all
        let timeout = TimeInterval(75)

        // When
        let (session, _) = await resolve(TestProperty(Timeout(timeout, for: requestTimeout)))

        // Then
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, timeout)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, timeout)
    }

    func testDefaultTimeout() async {
        let defaultConfiguration = URLSessionConfiguration.default

        // When
        let (session, _) = await resolve(TestProperty {})

        // Then
        XCTAssertEqual(
            session.configuration.timeoutIntervalForRequest,
            defaultConfiguration.timeoutIntervalForRequest
        )

        XCTAssertEqual(
            session.configuration.timeoutIntervalForResource,
            defaultConfiguration.timeoutIntervalForResource
        )
    }

    func testNeverBody() async throws {
        // Given
        let property = Timeout(1.0)

        // Then
        try await assertNever(property.body)
    }
}
