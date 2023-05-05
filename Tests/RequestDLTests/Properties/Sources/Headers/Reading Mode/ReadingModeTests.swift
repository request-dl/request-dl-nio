/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class ReadingModeTests: XCTestCase {

    func testReadingByLength() async throws {
        // Given
        let length = 1_024

        // When
        let (_, request) = try await resolve(TestProperty {
            ReadingMode(length: length)
        })

        // Then
        XCTAssertEqual(request.readingMode, .length(length))
    }

    func testReadingBySeparator() async throws {
        // Given
        let separator = Array(Data("\n".utf8))

        // When
        let (_, request) = try await resolve(TestProperty {
            ReadingMode(separator: separator)
        })

        // Then
        XCTAssertEqual(request.readingMode, .separator(separator))
    }
}
