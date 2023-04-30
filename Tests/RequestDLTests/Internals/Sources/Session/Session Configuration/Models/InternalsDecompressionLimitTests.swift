/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import NIOHTTPCompression
@testable import RequestDL

class InternalsDecompressionLimitTests: XCTestCase {

    func testLimit_whenNone() {
        // Given
        let limit = Internals.Decompression.Limit.none

        // When
        let sut = limit.build()

        // Then
        XCTAssertEqual(
            String(describing: sut),
            String(describing: NIOHTTPDecompression.DecompressionLimit.none)
        )
    }

    func testLimit_whenSize() {
        // Given
        let limit = Internals.Decompression.Limit.size(128)

        // When
        let sut = limit.build()

        // Then
        XCTAssertEqual(
            String(describing: sut),
            String(describing: NIOHTTPDecompression.DecompressionLimit.size(128))
        )
    }

    func testLimit_whenRatio() {
        // Given
        let limit = Internals.Decompression.Limit.ratio(1_024)

        // When
        let sut = limit.build()

        // Then
        XCTAssertEqual(
            String(describing: sut),
            String(describing: NIOHTTPDecompression.DecompressionLimit.ratio(1_024))
        )
    }

    func testLimit_whenEquals() {
        // Given
        let lhs = Internals.Decompression.Limit.ratio(1)
        let rhs = Internals.Decompression.Limit.ratio(1)

        // Then
        XCTAssertEqual(lhs, rhs)
    }

    func testLimit_whenNotEquals() {
        // Given
        let lhs = Internals.Decompression.Limit.none
        let rhs = Internals.Decompression.Limit.ratio(1)

        // Then
        XCTAssertNotEqual(lhs, rhs)
    }
}
