//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

/// `UnitTime` and Swift's `Duration`: what is kept, what is dropped, and where it saturates.
struct UnitTimeDurationTests {

    @Test
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    func init_fromADuration_keepsEveryWholeNanosecond() {
        #expect(UnitTime(.seconds(5)).nanoseconds == 5_000_000_000)
        #expect(UnitTime(.milliseconds(250)).nanoseconds == 250_000_000)
        #expect(UnitTime(.microseconds(3)).nanoseconds == 3_000)
        #expect(UnitTime(.nanoseconds(7)).nanoseconds == 7)
        #expect(UnitTime(.seconds(5) + .nanoseconds(7)).nanoseconds == 5_000_000_007)
        #expect(UnitTime(.zero).nanoseconds == 0)
    }

    @Test
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    func init_fromANegativeDuration_keepsItsSign() {
        #expect(UnitTime(.seconds(-5)).nanoseconds == -5_000_000_000)
        #expect(UnitTime(.seconds(-1) + .nanoseconds(-3)).nanoseconds == -1_000_000_003)
    }

    /// Below a nanosecond is dropped towards zero, on either side of it.
    @Test
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    func init_fromADuration_dropsWhatIsBelowANanosecondTowardsZero() {
        #expect(UnitTime(.nanoseconds(7) + Self.attoseconds(999_999_999)).nanoseconds == 7)
        #expect(UnitTime(Self.attoseconds(999_999_999)).nanoseconds == 0)
        #expect(UnitTime(Self.attoseconds(-999_999_999)).nanoseconds == 0)
        #expect(UnitTime(.nanoseconds(-7) + Self.attoseconds(-999_999_999)).nanoseconds == -7)
    }

    @Test
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    func init_fromADurationTooLongToCount_saturatesAtInfinity() {
        #expect(UnitTime(.seconds(Int64.max)) == .infinity)
        #expect(UnitTime(.seconds(300 * 365 * 24 * 3_600)) == .infinity)
        #expect(UnitTime(.seconds(Int64.max) + Self.attoseconds(999_999_999_999_999_999)) == .infinity)
    }

    @Test
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    func init_fromADurationTooLongToCountBackwards_saturatesAtTheSmallest() {
        #expect(UnitTime(.seconds(Int64.min)) == .nanoseconds(.min))
        #expect(UnitTime(.seconds(-300 * 365 * 24 * 3_600)) == .nanoseconds(.min))
    }

    @Test(arguments: [0, 1, -1, 1_500_000_000, Int64.max, Int64.min])
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    func duration_isTheSameTimeBackAgain(_ nanoseconds: Int64) {
        // Given
        let sut = UnitTime.nanoseconds(nanoseconds)

        // Then
        #expect(UnitTime(sut.duration) == sut)
    }

    @Test
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    func duration_ofInfinity_isTheLargestNumberOfNanoseconds() {
        #expect(UnitTime.infinity.duration == .nanoseconds(Int64.max))
    }

    @Test
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    func timeout_builtFromADuration_matchesTheSameTimeInSeconds() async throws {
        // When
        let resolved = try await resolve(
            TestProperty(Timeout(UnitTime(.seconds(42)), for: .read))
        )

        // Then
        #expect(resolved.session.configuration.timeout.read == UnitTime.seconds(42).nanoseconds)
    }

    // MARK: - Helpers

    /// `Duration` has no factory below a nanosecond, only its components.
    @available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
    private static func attoseconds(_ amount: Int64) -> Duration {
        Duration(secondsComponent: 0, attosecondsComponent: amount)
    }
}
