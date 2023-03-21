/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class TaskResultTests: XCTestCase {

    func testResult() async throws {
        // Given
        let response = URLResponse()
        let data = Data()

        // When
        let result = TaskResult(response: response, data: data)

        // Then
        XCTAssertEqual(result.response, response)
        XCTAssertEqual(result.payload, data)
    }
}
