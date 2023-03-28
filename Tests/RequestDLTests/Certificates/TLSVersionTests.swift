/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class TLSVersionTests: XCTestCase {

    func testVersion_whenV1_shouldBeV1() async throws {
        // Given
        let version: TLSVersion = .v1

        // When
        let sut = version.build()

        // Then
        XCTAssertEqual(sut, .tlsv1)
    }

    func testVersion_whenV11_shouldBeV11() async throws {
        // Given
        let version: TLSVersion = .v1_1

        // When
        let sut = version.build()

        // Then
        XCTAssertEqual(sut, .tlsv11)
    }

    func testVersion_whenV12_shouldBeV12() async throws {
        // Given
        let version: TLSVersion = .v1_2

        // When
        let sut = version.build()

        // Then
        XCTAssertEqual(sut, .tlsv12)
    }

    func testVersion_whenV13_shouldBeV13() async throws {
        // Given
        let version: TLSVersion = .v1_3

        // When
        let sut = version.build()

        // Then
        XCTAssertEqual(sut, .tlsv13)
    }
}
