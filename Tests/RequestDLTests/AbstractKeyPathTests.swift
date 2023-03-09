/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class AbstractKeyPathTests: XCTestCase {

    func testKeyPath() async throws {
        // Given
        func getValue(_ keyPath: KeyPath<AbstractKeyPath, String>) -> String {
            AbstractKeyPath()[keyPath: keyPath]
        }

        // When
        let keyPath = getValue(\.results)

        // Then
        XCTAssertEqual(keyPath, "results")
    }
}
