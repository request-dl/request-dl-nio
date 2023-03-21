/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class MockedTaskTests: XCTestCase {

    func testMock() async throws {
        // Given
        let statusCode = 200
        let headers = [
            "Content-Type": "application/json",
            "Accept": "text/html"
        ]
        let data = Data("Hello World".utf8)

        // When
        let result = try await MockedTask(
            statusCode: StatusCode(statusCode),
            headers: headers,
            data: { data }
        )
        .result()

        // Then
        let response = result.response as? HTTPURLResponse

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.statusCode, statusCode)
        XCTAssertEqual(result.payload, data)

        XCTAssertEqual(response?.allHeaderFields.keys.count, headers.keys.count)
        XCTAssertTrue(headers.keys.allSatisfy {
            headers[$0] == (response?.allHeaderFields[$0]).map {
                "\($0)"
            }
        })
    }

    func testDefaultValues() async throws {
        // Given
        let data = Data("Hello World".utf8)

        // When
        let result = try await MockedTask { data }
            .result()

        // Then
        let response = result.response as? HTTPURLResponse

        XCTAssertNotNil(response)
        XCTAssertEqual(response?.statusCode, 200)
        XCTAssertEqual(result.payload, data)
        XCTAssertTrue(response?.allHeaderFields.isEmpty ?? true)
    }
}
