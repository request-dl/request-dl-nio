/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ModifiersMapTests: XCTestCase {

    func testMap() async throws {
        // Given
        let output = 1

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
            Payload(data: Data())
        }
        .collectData()
        .map { _ in output }
        .result()

        // Then
        XCTAssertEqual(result, output)
    }
}
