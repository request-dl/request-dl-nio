/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

// swiftlint:disable type_name
final class URLSessionConfigurationRepresentableTests: XCTestCase {

    struct URLSessionConfigurationMock: URLSessionConfigurationRepresentable {

        func updateSessionConfiguration(_ sessionConfiguration: URLSessionConfiguration) {
            sessionConfiguration.timeoutIntervalForRequest = 15
            sessionConfiguration.timeoutIntervalForResource = 15
        }
    }

    func testUpdateRequest() async throws {
        // Given
        let property = URLSessionConfigurationMock()

        // When
        let (session, _) = try await resolve(TestProperty(property))

        // Then
        XCTAssertEqual(session.configuration.timeoutIntervalForRequest, 15)
        XCTAssertEqual(session.configuration.timeoutIntervalForResource, 15)
    }

    func testNeverBody() async throws {
        // Given
        let property = URLSessionConfigurationMock()

        // Then
        try await assertNever(property.body)
    }
}
