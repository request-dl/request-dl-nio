/*
 See LICENSE for this package's licensing information.
*/

import XCTest
import AsyncHTTPClient
@testable import RequestDL

class InternalsHTTPVersionTests: XCTestCase {

    func testVersion_whenHTTP1Only() {
        // Given
        let version = Internals.HTTPVersion.http1Only

        // When
        let sut = version.build()

        // Then
        XCTAssertEqual(sut, .http1Only)
    }

    func testVersion_whenAutomatic() {
        // Given
        let version = Internals.HTTPVersion.automatic

        // When
        let sut = version.build()

        // Then
        XCTAssertEqual(sut, .automatic)
    }

    func testVersion_whenEquals() {
        // Given
        let lhs = Internals.HTTPVersion.http1Only
        let rhs = Internals.HTTPVersion.http1Only

        // Then
        XCTAssertEqual(lhs, rhs)
    }

    func testVersion_whenNotEquals() {
        // Given
        let lhs = Internals.HTTPVersion.http1Only
        let rhs = Internals.HTTPVersion.automatic

        // Then
        XCTAssertNotEqual(lhs, rhs)
    }
}
