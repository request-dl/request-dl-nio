/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

public struct UnitTime: Hashable, Sendable {

    public let nanoseconds: Int64

    fileprivate init(_ nanoseconds: Int64) {
        self.nanoseconds = nanoseconds
    }
}

extension UnitTime: ExpressibleByIntegerLiteral {

    public init(integerLiteral value: Int64) {
        self.init(value)
    }
}

extension UnitTime {

    public static func nanoseconds(_ amount: Int64) -> UnitTime {
        .init(amount)
    }

    public static func microseconds(_ amount: Int64) -> UnitTime {
        amount * 1_000
    }

    public static func milliseconds(_ amount: Int64) -> UnitTime {
        amount * 1_000_000
    }

    public static func seconds(_ amount: Int64) -> UnitTime {
        amount * 1_000_000_000
    }

    public static func minutes(_ amount: Int64) -> UnitTime {
        amount * 60_000_000_000
    }

    public static func hours(_ amount: Int64) -> UnitTime {
        amount * 3_600_000_000_000
    }
}

extension UnitTime: Comparable {

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.nanoseconds < rhs.nanoseconds
    }
}

extension UnitTime: AdditiveArithmetic {

    public static var zero: UnitTime {
        0
    }

    public static func + (_ lhs: UnitTime, _ rhs: UnitTime) -> UnitTime {
        .init(lhs.nanoseconds + rhs.nanoseconds)
    }

    public static func +=(lhs: inout UnitTime, rhs: UnitTime) {
        lhs = lhs + rhs
    }

    public static func - (lhs: UnitTime, rhs: UnitTime) -> UnitTime {
        .init(lhs.nanoseconds - rhs.nanoseconds)
    }

    public static func -=(lhs: inout UnitTime, rhs: UnitTime) {
        lhs = lhs - rhs
    }

    public static func * <T: BinaryInteger>(lhs: T, rhs: UnitTime) -> UnitTime {
        .init(Int64(lhs) * rhs.nanoseconds)
    }

    public static func * <T: BinaryInteger>(lhs: UnitTime, rhs: T) -> UnitTime {
        .init(lhs.nanoseconds * Int64(rhs))
    }
}

extension UnitTime {

    func build() -> NIOCore.TimeAmount {
        .nanoseconds(Int64(nanoseconds))
    }
}
