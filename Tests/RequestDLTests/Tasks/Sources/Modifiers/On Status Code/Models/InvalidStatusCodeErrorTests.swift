/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class InvalidStatusCodeErrorTests: XCTestCase {

    func testError() async throws {
        // Given
        let error = InvalidStatusCodeError(data: true)

        // Then
        XCTAssertTrue(error.data)
    }
}
