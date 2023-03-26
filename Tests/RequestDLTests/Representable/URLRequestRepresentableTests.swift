/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class URLRequestRepresentableTests: XCTestCase {

    struct URLRequestMock: URLRequestRepresentable {

        func updateRequest(_ request: inout URLRequest) {
            request.setValue("password", forHTTPHeaderField: "api_key")
        }
    }

    func testUpdateRequest() async throws {
        // Given
        let property = URLRequestMock()

        // When
        let (_, request) = try await resolve(TestProperty(property))

        // Then
        XCTAssertEqual(request.value(forHTTPHeaderField: "api_key"), "password")
    }

    func testNeverBody() async throws {
        // Given
        let property = URLRequestMock()

        // Then
        try await assertNever(property.body)
    }
}
