/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class UnitTimeTests: XCTestCase {

    func testUnitTime_whenNanoseconds_shouldBeValid() async throws {
        // Given
        let nanoseconds: Int64 = 6

        // When
        let sut = UnitTime.nanoseconds(nanoseconds)

        // Then
        XCTAssertEqual(sut.nanoseconds, 6)
    }

    func testUnitTime_whenMicroseconds_shouldBeValid() async throws {
        // Given
        let microseconds: Int64 = 6

        // When
        let sut = UnitTime.microseconds(microseconds)

        // Then
        XCTAssertEqual(sut.nanoseconds, microseconds * 1_000)
    }

    func testUnitTime_whenMilliseconds_shouldBeValid() async throws {
        // Given
        let milliseconds: Int64 = 6

        // When
        let sut = UnitTime.milliseconds(milliseconds)

        // Then
        XCTAssertEqual(sut.nanoseconds, milliseconds * 1_000_000)
    }

    func testUnitTime_whenSeconds_shouldBeValid() async throws {
        // Given
        let seconds: Int64 = 6

        // When
        let sut = UnitTime.seconds(seconds)

        // Then
        XCTAssertEqual(sut.nanoseconds, seconds * 1_000_000_000)
    }

    func testUnitTime_whenMinutes_shouldBeValid() async throws {
        // Given
        let minutes: Int64 = 6

        // When
        let sut = UnitTime.minutes(minutes)

        // Then
        XCTAssertEqual(sut.nanoseconds, minutes * 60_000_000_000)
    }

    func testUnitTime_whenHours_shouldBeValid() async throws {
        // Given
        let hours: Int64 = 6

        // When
        let sut = UnitTime.hours(hours)

        // Then
        XCTAssertEqual(sut.nanoseconds, hours * 3_600_000_000_000)
    }

    func testUnitTime_whenCompareSecondsToMilliseconds_shouldBeGreater() async throws {
        // Given
        let lhs: UnitTime = .seconds(6)
        let rhs: UnitTime = .milliseconds(6)

        // Then
        XCTAssertGreaterThan(lhs, rhs)
    }

    func testUnitTime_whenCompareNanosecondsToHours_shouldBeLower() async throws {
        // Given
        let lhs: UnitTime = .nanoseconds(6)
        let rhs: UnitTime = .hours(6)

        // Then
        XCTAssertLessThan(lhs, rhs)
    }

    func testUnitTime_whenAddSecondsToHours_shouldValid() async throws {
        // Given
        let lhs: UnitTime = .seconds(6)
        let rhs: UnitTime = .hours(6)

        // Then
        XCTAssertEqual(
            (lhs + rhs).nanoseconds,
            lhs.nanoseconds + rhs.nanoseconds
        )
    }

    func testUnitTime_whenSubtractSecondsFormHours_shouldValid() async throws {
        // Given
        let lhs: UnitTime = .hours(6)
        let rhs: UnitTime = .seconds(6)

        // Then
        XCTAssertEqual(
            (lhs - rhs).nanoseconds,
            lhs.nanoseconds - rhs.nanoseconds
        )
    }

    func testUnitTime_whenHashable_shouldValid() async throws {
        // Given
        let sut: Set<UnitTime> = [.seconds(6), .seconds(6), .hours(10)]

        // Then
        XCTAssertEqual(sut, [.seconds(6), .hours(10)])
    }

    func testUnitTime_whenZero_shouldBeValid() async throws {
        XCTAssertEqual(UnitTime.zero.nanoseconds, .zero)
    }

    func testUnitTime_whenMultiply_shouldBeValid() async throws {
        // Given
        let lhs = UnitTime.seconds(10)
        let rhs = UnitTime.hours(5)

        let multiplier: (Int64, Int64) = (3, 5)

        // When
        let result = (
            lhs * multiplier.0,
            multiplier.1 * rhs
        )

        // Then
        XCTAssertEqual(result.0.nanoseconds, 10 * multiplier.0 * 1_000_000_000)
        XCTAssertEqual(result.1.nanoseconds, 5 * multiplier.1 * 3_600_000_000_000)
    }

    func testUnitTime_whenAddWhileAssigning_shouldBeValid() async throws {
        // Given
        var value = UnitTime.nanoseconds(1)

        // When
        value += .nanoseconds(5)

        // Then
        XCTAssertEqual(value.nanoseconds, 6)
    }

    func testUnitTime_whenSubtractWhileAssigning_shouldBeValid() async throws {
        // Given
        var value = UnitTime.nanoseconds(1)

        // When
        value -= .nanoseconds(5)

        // Then
        XCTAssertEqual(value.nanoseconds, -4)
    }
}
