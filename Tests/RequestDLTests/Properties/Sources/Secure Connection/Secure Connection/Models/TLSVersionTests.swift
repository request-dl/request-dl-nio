/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
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

    func testVersion_whenComparableV1WithV11_shouldBeLower() async throws {
        // Given
        let lhs: TLSVersion = .v1
        let rhs: TLSVersion = .v1_1

        // Then
        XCTAssertLessThan(lhs, rhs)
    }

    func testVersion_whenComparableV11WithV13_shouldBeLower() async throws {
        // Given
        let lhs: TLSVersion = .v1_1
        let rhs: TLSVersion = .v1_3

        // Then
        XCTAssertLessThan(lhs, rhs)
    }

    func testVersion_whenComparableV12WithV1_shouldBeGreater() async throws {
        // Given
        let lhs: TLSVersion = .v1_2
        let rhs: TLSVersion = .v1

        // Then
        XCTAssertGreaterThan(lhs, rhs)
    }
}
