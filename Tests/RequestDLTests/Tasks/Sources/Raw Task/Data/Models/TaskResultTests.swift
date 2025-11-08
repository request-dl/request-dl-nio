/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct TaskResultTests {

    @Test
    func result() async throws {
        // Given
        let head = ResponseHead(
            url: nil,
            status: .init(code: 101, reason: ""),
            version: .init(minor: 0, major: 1),
            headers: .init([("Content-Type", "application/json")]),
            isKeepAlive: false
        )

        let data = Data()

        // When
        let result = TaskResult(head: head, payload: data)

        // Then
        #expect(result.head == head)
        #expect(result.payload == data)
    }
}
