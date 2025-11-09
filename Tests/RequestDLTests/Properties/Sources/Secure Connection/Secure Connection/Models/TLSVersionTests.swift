/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct TLSVersionTests {

    @Test
    func version_whenV1_shouldBeV1() async throws {
        // Given
        let version: TLSVersion = .v1

        // When
        let sut = version.build()

        // Then
        #expect(sut == .tlsv1)
    }

    @Test
    func version_whenV11_shouldBeV11() async throws {
        // Given
        let version: TLSVersion = .v1_1

        // When
        let sut = version.build()

        // Then
        #expect(sut == .tlsv11)
    }

    @Test
    func version_whenV12_shouldBeV12() async throws {
        // Given
        let version: TLSVersion = .v1_2

        // When
        let sut = version.build()

        // Then
        #expect(sut == .tlsv12)
    }

    @Test
    func version_whenV13_shouldBeV13() async throws {
        // Given
        let version: TLSVersion = .v1_3

        // When
        let sut = version.build()

        // Then
        #expect(sut == .tlsv13)
    }

    @Test
    func version_whenComparableV1WithV11_shouldBeLower() async throws {
        // Given
        let lhs: TLSVersion = .v1
        let rhs: TLSVersion = .v1_1

        // Then
        #expect(lhs < rhs)
    }

    @Test
    func version_whenComparableV11WithV13_shouldBeLower() async throws {
        // Given
        let lhs: TLSVersion = .v1_1
        let rhs: TLSVersion = .v1_3

        // Then
        #expect(lhs < rhs)
    }

    @Test
    func version_whenComparableV12WithV1_shouldBeGreater() async throws {
        // Given
        let lhs: TLSVersion = .v1_2
        let rhs: TLSVersion = .v1

        // Then
        #expect(lhs > rhs)
    }
}
