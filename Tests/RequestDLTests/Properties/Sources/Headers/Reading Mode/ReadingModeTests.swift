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
        let (session, _) = try await resolve(TestProperty {
            ReadingMode(length: length)
        })

        // Then
        XCTAssertEqual(session.configuration.readingMode, .length(length))
    }

    func testReadingBySeparator() async throws {
        // Given
        let separator = Array(Data("\n".utf8))

        // When
        let (session, _) = try await resolve(TestProperty {
            ReadingMode(separator: separator)
        })

        // Then
        XCTAssertEqual(session.configuration.readingMode, .separator(separator))
    }
}
