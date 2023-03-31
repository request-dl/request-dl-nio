/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 A struct representing a duration of time, with support for various units.

 Use `UnitTime` to represent a duration of time in your app.
 */
public struct UnitTime: Hashable, Sendable {

    /// The duration of time in nanoseconds.
    public let nanoseconds: Int64

    fileprivate init(_ nanoseconds: Int64) {
        self.nanoseconds = nanoseconds
    }
}

extension UnitTime {

    /**
     Creates a `UnitTime` instance with the specified duration in nanoseconds.

     - Parameter amount: The duration of time in nanoseconds.
     - Returns: A new `UnitTime` instance.
     */
    public static func nanoseconds(_ amount: Int64) -> UnitTime {
        .init(amount)
    }

    /**
     Creates a `UnitTime` instance with the specified duration in microseconds.

     - Parameter amount: The duration of time in microseconds.
     - Returns: A new `UnitTime` instance.
     */
    public static func microseconds(_ amount: Int64) -> UnitTime {
        .nanoseconds(amount * 1_000)
    }

    /**
     Creates a `UnitTime` instance with the specified duration in milliseconds.

     - Parameter amount: The duration of time in milliseconds.
     - Returns: A new `UnitTime` instance.
     */
    public static func milliseconds(_ amount: Int64) -> UnitTime {
        .nanoseconds(amount * 1_000_000)
    }

    /**
     Creates a `UnitTime` instance with the specified duration in seconds.

     - Parameter amount: The duration of time in seconds.
     - Returns: A new `UnitTime` instance.
     */
    public static func seconds(_ amount: Int64) -> UnitTime {
        .nanoseconds(amount * 1_000_000_000)
    }

    /**
     Creates a `UnitTime` instance with the specified duration in minutes.

     - Parameter amount: The duration of time in minutes.
     - Returns: A new `UnitTime` instance.
     */
    public static func minutes(_ amount: Int64) -> UnitTime {
        .nanoseconds(amount * 60_000_000_000)
    }

    /**
     Creates a `UnitTime` instance with the specified duration in hours.

     - Parameter amount: The duration of time in hours.
     - Returns: A new `UnitTime` instance.
     */
    public static func hours(_ amount: Int64) -> UnitTime {
        .nanoseconds(amount * 3_600_000_000_000)
    }
}

extension UnitTime: Comparable {

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }
}

extension UnitTime: AdditiveArithmetic {

    public static var zero: UnitTime {
        .nanoseconds(.zero)
    }

    public static func + (_ lhs: UnitTime, _ rhs: UnitTime) -> UnitTime {
        .init(lhs.nanoseconds + rhs.nanoseconds)
    }

    public static func += (lhs: inout UnitTime, rhs: UnitTime) {
        lhs = lhs + rhs
    }

    public static func - (lhs: UnitTime, rhs: UnitTime) -> UnitTime {
        .init(lhs.nanoseconds - rhs.nanoseconds)
    }

    public static func -= (lhs: inout UnitTime, rhs: UnitTime) {
        lhs = lhs - rhs
    }

    /**
     Multiplies a binary integer by a `UnitTime`.

     - Parameters:
        - lhs: The binary integer to multiply.
        - rhs: The `UnitTime` to multiply.
     - Returns: A new `UnitTime` instance with the calculated duration.
     */
    public static func * <T: BinaryInteger>(lhs: T, rhs: UnitTime) -> UnitTime {
        .init(Int64(lhs) * rhs.nanoseconds)
    }

    /**
     Multiplies a `UnitTime` by a binary integer.

     - Parameters:
        - lhs: The `UnitTime` to multiply.
        - rhs: The binary integer to multiply.
     - Returns: A new `UnitTime` instance with the calculated duration.
     */
    public static func * <T: BinaryInteger>(lhs: UnitTime, rhs: T) -> UnitTime {
        .init(lhs.nanoseconds * Int64(rhs))
    }
}
