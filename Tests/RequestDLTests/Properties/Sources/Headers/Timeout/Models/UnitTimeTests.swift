/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

@RequestActor
class UnitTimeTests: XCTestCase {

    func testUnitTime_whenNanoseconds_shouldBeValid() async throws {
        // Given
        let nanoseconds: Int64 = 6

        // When
        let sut = UnitTime.nanoseconds(nanoseconds)

        // Then
        XCTAssertEqual(sut.build(), .nanoseconds(nanoseconds))
    }

    func testUnitTime_whenMicroseconds_shouldBeValid() async throws {
        // Given
        let microseconds: Int64 = 6

        // When
        let sut = UnitTime.microseconds(microseconds)

        // Then
        XCTAssertEqual(sut.build(), .microseconds(microseconds))
    }

    func testUnitTime_whenMilliseconds_shouldBeValid() async throws {
        // Given
        let milliseconds: Int64 = 6

        // When
        let sut = UnitTime.milliseconds(milliseconds)

        // Then
        XCTAssertEqual(sut.build(), .milliseconds(milliseconds))
    }

    func testUnitTime_whenSeconds_shouldBeValid() async throws {
        // Given
        let seconds: Int64 = 6

        // When
        let sut = UnitTime.seconds(seconds)

        // Then
        XCTAssertEqual(sut.build(), .seconds(seconds))
    }

    func testUnitTime_whenMinutes_shouldBeValid() async throws {
        // Given
        let minutes: Int64 = 6

        // When
        let sut = UnitTime.minutes(minutes)

        // Then
        XCTAssertEqual(sut.build(), .minutes(minutes))
    }

    func testUnitTime_whenHours_shouldBeValid() async throws {
        // Given
        let hours: Int64 = 6

        // When
        let sut = UnitTime.hours(hours)

        // Then
        XCTAssertEqual(sut.build(), .hours(hours))
    }

    func testUnitTime_whenInteger_shouldBeValid() async throws {
        // Given
        let nanoseconds: UnitTime = 6

        // Then
        XCTAssertEqual(nanoseconds.nanoseconds, 6)
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
            (lhs.build() + rhs.build()).nanoseconds
        )
    }

    func testUnitTime_whenSubtractSecondsFormHours_shouldValid() async throws {
        // Given
        let lhs: UnitTime = .hours(6)
        let rhs: UnitTime = .seconds(6)

        // Then
        XCTAssertEqual(
            (lhs - rhs).nanoseconds,
            (lhs.build() - rhs.build()).nanoseconds
        )
    }

    func testUnitTime_whenHashable_shouldValid() async throws {
        // Given
        let sut: Set<UnitTime> = [.seconds(6), .seconds(6), .hours(10)]

        // Then
        XCTAssertEqual(sut, [.seconds(6), .hours(10)])
    }

    func testUnitTime_whenZero() async throws {
        // Given
        let sut = UnitTime.zero

        // Then
        XCTAssertEqual(sut.nanoseconds, .zero)
    }

    func testUnitTime_whenAddingWithAssignment() async throws {
        // Given
        var lhs = UnitTime.zero
        let rhs = UnitTime.hours(1)

        // When
        lhs += rhs

        // Then
        XCTAssertEqual(lhs, .hours(1))
    }

    func testUnitTime_whenSubtractingWithAssignment() async throws {
        // Given
        var lhs = UnitTime.hours(1)
        let rhs = UnitTime.minutes(45)

        // When
        lhs -= rhs

        // Then
        XCTAssertEqual(lhs, .minutes(15))
    }

    func testUnitTime_whenMultiplying() async throws {
        // Given
        let lhs = UnitTime.hours(1)
        let value = 2

        // When

        // Then
        XCTAssertEqual(lhs * value, .hours(2))
    }

    func testUnitTime_withStringLossless() async throws {
        // Given
        let unitTime = UnitTime.seconds(1)

        // When
        let string = String(unitTime)
        let losslessUnitTime = UnitTime(string)

        // Then
        XCTAssertEqual(string, unitTime.description)
        XCTAssertEqual(losslessUnitTime, unitTime)
    }
}
