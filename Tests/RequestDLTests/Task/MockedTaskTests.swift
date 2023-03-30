/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class MockedTaskTests: XCTestCase {

    func testMock() async throws {
        // Given
        let statusCode: UInt = 200
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
        let response = result.head

        XCTAssertNotNil(response)
        XCTAssertEqual(response.status.code, statusCode)
        XCTAssertEqual(result.payload, data)

        XCTAssertEqual(response.headers.count, headers.count)
        XCTAssertTrue(headers.keys.allSatisfy {
            headers[$0] == response.headers.getValue(forKey: $0)
        })
    }

    func testDefaultValues() async throws {
        // Given
        let data = Data("Hello World".utf8)

        // When
        let result = try await MockedTask { data }
            .result()

        // Then
        let head = result.head

        XCTAssertEqual(head.status.code, 200)
        XCTAssertEqual(result.payload, data)
        XCTAssertTrue(head.headers.isEmpty)
    }
}
