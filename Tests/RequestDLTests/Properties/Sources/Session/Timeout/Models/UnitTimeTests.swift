/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct UnitTimeTests {

    @Test
    func unitTime_whenNanoseconds_shouldBeValid() async throws {
        // Given
        let nanoseconds: Int64 = 6

        // When
        let sut = UnitTime.nanoseconds(nanoseconds)

        // Then
        #expect(sut.build() == .nanoseconds(nanoseconds))
    }

    @Test
    func unitTime_whenMicroseconds_shouldBeValid() async throws {
        // Given
        let microseconds: Int64 = 6

        // When
        let sut = UnitTime.microseconds(microseconds)

        // Then
        #expect(sut.build() == .microseconds(microseconds))
    }

    @Test
    func unitTime_whenMilliseconds_shouldBeValid() async throws {
        // Given
        let milliseconds: Int64 = 6

        // When
        let sut = UnitTime.milliseconds(milliseconds)

        // Then
        #expect(sut.build() == .milliseconds(milliseconds))
    }

    @Test
    func unitTime_whenSeconds_shouldBeValid() async throws {
        // Given
        let seconds: Int64 = 6

        // When
        let sut = UnitTime.seconds(seconds)

        // Then
        #expect(sut.build() == .seconds(seconds))
    }

    @Test
    func unitTime_whenMinutes_shouldBeValid() async throws {
        // Given
        let minutes: Int64 = 6

        // When
        let sut = UnitTime.minutes(minutes)

        // Then
        #expect(sut.build() == .minutes(minutes))
    }

    @Test
    func unitTime_whenHours_shouldBeValid() async throws {
        // Given
        let hours: Int64 = 6

        // When
        let sut = UnitTime.hours(hours)

        // Then
        #expect(sut.build() == .hours(hours))
    }

    @Test
    func unitTime_whenInteger_shouldBeValid() async throws {
        // Given
        let nanoseconds: UnitTime = 6

        // Then
        #expect(nanoseconds.nanoseconds == 6)
    }

    @Test
    func unitTime_whenCompareSecondsToMilliseconds_shouldBeGreater() async throws {
        // Given
        let lhs: UnitTime = .seconds(6)
        let rhs: UnitTime = .milliseconds(6)

        // Then
        #expect(lhs > rhs)
    }

    @Test
    func unitTime_whenCompareNanosecondsToHours_shouldBeLower() async throws {
        // Given
        let lhs: UnitTime = .nanoseconds(6)
        let rhs: UnitTime = .hours(6)

        // Then
        #expect(lhs < rhs)
    }

    @Test
    func unitTime_whenAddSecondsToHours_shouldValid() async throws {
        // Given
        let lhs: UnitTime = .seconds(6)
        let rhs: UnitTime = .hours(6)

        // Then
        #expect(
            (lhs + rhs).nanoseconds,
            (lhs.build() + rhs.build()).nanoseconds
        )
    }

    @Test
    func unitTime_whenSubtractSecondsFormHours_shouldValid() async throws {
        // Given
        let lhs: UnitTime = .hours(6)
        let rhs: UnitTime = .seconds(6)

        // Then
        #expect(
            (lhs - rhs).nanoseconds,
            (lhs.build() - rhs.build()).nanoseconds
        )
    }

    @Test
    func unitTime_whenHashable_shouldValid() async throws {
        // Given
        let sut: Set<UnitTime> = [.seconds(6), .seconds(6), .hours(10)]

        // Then
        #expect(sut, [.seconds(6) == .hours(10)])
    }

    @Test
    func unitTime_whenZero() async throws {
        // Given
        let sut = UnitTime.zero

        // Then
        #expect(sut.nanoseconds == .zero)
    }

    @Test
    func unitTime_whenAddingWithAssignment() async throws {
        // Given
        var lhs = UnitTime.zero
        let rhs = UnitTime.hours(1)

        // When
        lhs += rhs

        // Then
        #expect(lhs == .hours(1))
    }

    @Test
    func unitTime_whenSubtractingWithAssignment() async throws {
        // Given
        var lhs = UnitTime.hours(1)
        let rhs = UnitTime.minutes(45)

        // When
        lhs -= rhs

        // Then
        #expect(lhs == .minutes(15))
    }

    @Test
    func unitTime_whenMultiplying() async throws {
        // Given
        let lhs = UnitTime.hours(1)
        let value = 2

        // When

        // Then
        #expect(lhs * value == .hours(2))
    }

    @Test
    func unitTime_withStringLossless() async throws {
        // Given
        let unitTime = UnitTime.seconds(1)

        // When
        let string = String(unitTime)
        let losslessUnitTime = UnitTime(string)

        // Then
        #expect(string == unitTime.description)
        #expect(losslessUnitTime == unitTime)
    }
}
