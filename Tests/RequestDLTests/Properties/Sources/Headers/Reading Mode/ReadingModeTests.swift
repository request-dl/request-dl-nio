/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class ReadingModeTests: XCTestCase {

    func testReadingByLength() async throws {
        // Given
        let length = 1_024

        // When
        let resolved = try await resolve(TestProperty {
            ReadingMode(length: length)
        })

        // Then
        XCTAssertEqual(resolved.request.readingMode, .length(length))
    }

    func testReadingBySeparator() async throws {
        // Given
        let separator = Array(Data("\n".utf8))

        // When
        let resolved = try await resolve(TestProperty {
            ReadingMode(separator: separator)
        })

        // Then
        XCTAssertEqual(resolved.request.readingMode, .separator(separator))
    }
}
