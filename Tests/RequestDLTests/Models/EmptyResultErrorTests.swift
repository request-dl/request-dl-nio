/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class EmptyResponseErrorTests: XCTestCase {

    func testError() async throws {
        // Given
        let error = EmptyResultError()

        // Then
        XCTAssertEqual(error.errorDescription, "The result was empty.")
    }
}
