/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class TaskResultTests: XCTestCase {

    func testResult() async throws {
        // Given
        let head = ResponseHead(
            url: nil,
            status: .init(code: 101, reason: ""),
            version: .init(minor: 0, major: 1),
            headers: .init(["Content-Type": "application/json"]),
            isKeepAlive: false
        )

        let data = Data()

        // When
        let result = TaskResult(head: head, payload: data)

        // Then
        XCTAssertEqual(result.head, head)
        XCTAssertEqual(result.payload, data)
    }
}
