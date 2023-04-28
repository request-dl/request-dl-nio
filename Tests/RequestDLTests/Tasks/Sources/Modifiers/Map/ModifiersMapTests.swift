/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class ModifiersMapTests: XCTestCase {

    func testMap() async throws {
        // Given
        let output = 1

        // When
        let result = try await MockedTask(data: Data.init)
            .map { _ in output }
            .result()

        // Then
        XCTAssertEqual(result, output)
    }
}
