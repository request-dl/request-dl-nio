/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class KeyPathNotFoundTests: XCTestCase {

    func testError() async throws {
        // Given
        let keyPath = "any"

        // When
        let error = KeyPathNotFound(keyPath: keyPath)

        // Then
        XCTAssertEqual(error.errorDescription, "Unable to resolve the KeyPath.\(keyPath) in the current Task result")
    }
}
