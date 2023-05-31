/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class TaskMethodsTests: XCTestCase {

    func testPinging() async throws {
        // Given
        let data = Data()

        // When
        try await MockedTask(content: {
            BaseURL("localhost")
            Payload(data: data)
        })
        .ping(10)
    }
}
