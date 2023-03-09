/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class KeyPathInvalidDataErrorTests: XCTestCase {

    func testError() async throws {
        // Given
        let error = KeyPathInvalidDataError()

        // Then
        XCTAssertEqual(error.errorDescription,
            """
            Unable to read the current data result on Task.keyPath() in key-value format
            """
        )
    }
}
