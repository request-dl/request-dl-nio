/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class AnyTaskTests: XCTestCase {

    func testAnyTask() async throws {
        // Given
        let data = Data("123".utf8)

        // When
        let result = try await MockedTask { data }
            .eraseToAnyTask()
            .result()

        // Then
        XCTAssertEqual(result.payload, data)
    }
}
