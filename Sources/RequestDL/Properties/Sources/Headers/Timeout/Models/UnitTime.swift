/*
 See LICENSE for this package's licensing information.
 */

import Foundation
import NIOCore

/**
 A unit of time represented in nanoseconds.

 Use this struct to represent time intervals with nanosecond precision.

 Conforms to Hashable and Sendable protocols.

 > Note: The maximum representable time interval is limited by the range of Int64.

 > Warning: Be careful when working with large time intervals to avoid overflow.

 - Remark: Time intervals can be created using various factory methods, such as `nanoseconds(_:)`,
 `microseconds(_:)`, `milliseconds(_:)`, `seconds(_:)`, `minutes(_:)`, and
 `hours(_:)`.
 */
public struct UnitTime: Sendable, Hashable {

    // MARK: - Public properties

    /// The time interval in nanoseconds.
    public let nanoseconds: Int64

    // MARK: - Inits

    fileprivate init(_ nanoseconds: Int64) {
        self.nanoseconds = nanoseconds
    }

    // MARK: - Public static methods

    /**
     Creates a `UnitTime` representing the specified number of nanoseconds.

     - Parameter amount: The number of nanoseconds.
     - Returns: A `UnitTime` representing the specified number of nanoseconds.
     */
    public static func nanoseconds(_ amount: Int64) -> UnitTime {
        .init(amount)
    }

    /**
     Creates a `UnitTime` representing the specified number of microseconds.

     - Parameter amount: The number of microseconds.
     - Returns: A `UnitTime` representing the specified number of microseconds.
     */
    public static func microseconds(_ amount: Int64) -> UnitTime {
        amount * 1_000
    }

    /**
     Creates a `UnitTime` representing the specified number of milliseconds.

     - Parameter amount: The number of milliseconds.
     - Returns: A `UnitTime` representing the specified number of milliseconds.
     */
    public static func milliseconds(_ amount: Int64) -> UnitTime {
        amount * 1_000_000
    }

    /**
     Creates a `UnitTime` representing the specified number of seconds.

     - Parameter amount: The number of seconds.
     - Returns: A `UnitTime` representing the specified number of seconds.
     */
    public static func seconds(_ amount: Int64) -> UnitTime {
        amount * 1_000_000_000
    }

    /**
     Creates a `UnitTime` representing the specified number of minutes.

     - Parameter amount: The number of minutes.
     - Returns: A `UnitTime` representing the specified number of minutes.
     */
    public static func minutes(_ amount: Int64) -> UnitTime {
        amount * 60_000_000_000
    }

    /**
     Creates a `UnitTime` representing the specified number of hours.

     - Parameter amount: The number of hours.
     - Returns: A `UnitTime` representing the specified number of hours.
     */
    public static func hours(_ amount: Int64) -> UnitTime {
        amount * 3_600_000_000_000
    }

    // MARK: - Internal methods
    func build() -> NIOCore.TimeAmount {
        .nanoseconds(Int64(nanoseconds))
    }
}

// MARK: - ExpressibleByIntegerLiteral

extension UnitTime: ExpressibleByIntegerLiteral {

    public init(integerLiteral value: Int64) {
        self.init(value)
    }
}

// MARK: - LosslessStringConvertible

extension UnitTime: LosslessStringConvertible {

    public init?(_ description: String) {
        guard let nanoseconds = Int64(description) else {
            return nil
        }

        self.nanoseconds = nanoseconds
    }

    public var description: String {
        String(nanoseconds)
    }
}

// MARK: - Comparable

extension UnitTime: Comparable {

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }
}

// MARK: - AdditiveArithmetic

extension UnitTime: AdditiveArithmetic {

    public static var zero: UnitTime {
        0
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
     Multiplies a unit of time by an integer value.

     - Parameters:
     - lhs: The integer value to multiply.
     - rhs: The unit of time to multiply.
     - Returns: A `UnitTime` representing the result of multiplying the unit of time by the integer value.
     */
    public static func * <T: BinaryInteger>(lhs: T, rhs: UnitTime) -> UnitTime {
        .init(Int64(lhs) * rhs.nanoseconds)
    }

    /**
     Multiplies a unit of time by an integer value.

     - Parameters:
     - lhs: The unit of time to multiply.
     - rhs: The integer value to multiply.
     - Returns: A `UnitTime` representing the result of multiplying the unit of time by the integer value.
     */
    public static func * <T: BinaryInteger>(lhs: UnitTime, rhs: T) -> UnitTime {
        .init(lhs.nanoseconds * Int64(rhs))
    }
}
