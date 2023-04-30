/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import AsyncHTTPClient
@testable import RequestDL

class InternalsDecompressionTests: XCTestCase {

    func testDecompression_whenDisabled() {
        // Given
        let decompression = Internals.Decompression.disabled

        // When
        let sut = decompression.build()

        // Then
        XCTAssertEqual(
            String(describing: sut),
            String(describing: HTTPClient.Decompression.disabled)
        )
    }

    func testDecompression_whenEnabled() {
        // Given
        let decompression = Internals.Decompression.enabled(.ratio(1_024))

        // When
        let sut = decompression.build()

        // Then
        XCTAssertEqual(
            String(describing: sut),
            String(describing: HTTPClient.Decompression.enabled(limit: .ratio(1_024)))
        )
    }

    func testDecompression_whenEquals() {
        // Given
        let lhs = Internals.Decompression.disabled
        let rhs = Internals.Decompression.disabled

        // Then
        XCTAssertEqual(lhs, rhs)
    }

    func testDecompression_whenNotEquals() {
        // Given
        let lhs = Internals.Decompression.disabled
        let rhs = Internals.Decompression.enabled(.none)

        // Then
        XCTAssertNotEqual(lhs, rhs)
    }
}
