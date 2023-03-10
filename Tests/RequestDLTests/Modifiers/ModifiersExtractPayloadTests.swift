/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class ModifiersExtractPayloadTests: XCTestCase {

    func testExtractPayload() async throws {
        // Given
        let data = Data("--".utf8)

        // When
        let result = try await MockedTask { data }
            .extractPayload()
            .result()

        // Then
        XCTAssertEqual(result, data)
    }
}
