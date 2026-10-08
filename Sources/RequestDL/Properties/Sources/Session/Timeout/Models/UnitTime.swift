//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOCore
#endif

/// A unit of time represented in nanoseconds.
///
/// Use this struct to represent time intervals with nanosecond precision.
///
/// Conforms to Hashable and Sendable protocols.
///
/// > Note: The maximum representable time interval is limited by the range of Int64. An amount
/// or an operation that goes past it saturates at ``Int64/max`` (or ``Int64/min``) instead of
/// trapping, so a value read from the environment can't crash the process.
///
/// - Remark: Time intervals can be created using various factory methods, such as `nanoseconds(_:)`,
/// `microseconds(_:)`, `milliseconds(_:)`, `seconds(_:)`, `minutes(_:)`, and
/// `hours(_:)`.
public struct UnitTime: Sendable, Hashable {

    // MARK: - Public properties

    /// The time interval in nanoseconds.
    public let nanoseconds: Int64

    // MARK: - Inits

    fileprivate init(_ nanoseconds: Int64) {
        self.nanoseconds = nanoseconds
    }

    fileprivate init(saturating amount: Int64, perUnit nanoseconds: Int64) {
        let (product, overflow) = amount.multipliedReportingOverflow(by: nanoseconds)
        self.nanoseconds = overflow ? ((amount < 0) != (nanoseconds < 0) ? .min : .max) : product
    }

    // MARK: - Public static methods

    ///
    /// Creates a `UnitTime` representing the specified number of nanoseconds.
    ///
    /// - Parameter amount: The number of nanoseconds.
    /// - Returns: A `UnitTime` representing the specified number of nanoseconds.
    ///
    public static func nanoseconds(_ amount: Int64) -> UnitTime {
        .init(amount)
    }

    ///
    /// Creates a `UnitTime` representing the specified number of microseconds.
    ///
    /// - Parameter amount: The number of microseconds.
    /// - Returns: A `UnitTime` representing the specified number of microseconds.
    ///
    public static func microseconds(_ amount: Int64) -> UnitTime {
        .init(saturating: amount, perUnit: 1_000)
    }

    ///
    /// Creates a `UnitTime` representing the specified number of milliseconds.
    ///
    /// - Parameter amount: The number of milliseconds.
    /// - Returns: A `UnitTime` representing the specified number of milliseconds.
    ///
    public static func milliseconds(_ amount: Int64) -> UnitTime {
        .init(saturating: amount, perUnit: 1_000_000)
    }

    ///
    /// Creates a `UnitTime` representing the specified number of seconds.
    ///
    /// - Parameter amount: The number of seconds.
    /// - Returns: A `UnitTime` representing the specified number of seconds.
    ///
    public static func seconds(_ amount: Int64) -> UnitTime {
        .init(saturating: amount, perUnit: 1_000_000_000)
    }

    ///
    /// Creates a `UnitTime` representing the specified number of minutes.
    ///
    /// - Parameter amount: The number of minutes.
    /// - Returns: A `UnitTime` representing the specified number of minutes.
    ///
    public static func minutes(_ amount: Int64) -> UnitTime {
        .init(saturating: amount, perUnit: 60_000_000_000)
    }

    ///
    /// Creates a `UnitTime` representing the specified number of hours.
    ///
    /// - Parameter amount: The number of hours.
    /// - Returns: A `UnitTime` representing the specified number of hours.
    ///
    public static func hours(_ amount: Int64) -> UnitTime {
        .init(saturating: amount, perUnit: 3_600_000_000_000)
    }

    // MARK: - Internal methods
    #if canImport(NIOCore)
    func build() -> NIOCore.TimeAmount {
        .nanoseconds(Int64(nanoseconds))
    }
    #endif
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
        let (sum, overflow) = lhs.nanoseconds.addingReportingOverflow(rhs.nanoseconds)
        return .init(overflow ? (rhs.nanoseconds < 0 ? .min : .max) : sum)
    }

    public static func += (lhs: inout UnitTime, rhs: UnitTime) {
        lhs = lhs + rhs
    }

    public static func - (lhs: UnitTime, rhs: UnitTime) -> UnitTime {
        let (difference, overflow) = lhs.nanoseconds.subtractingReportingOverflow(rhs.nanoseconds)
        return .init(overflow ? (rhs.nanoseconds < 0 ? .max : .min) : difference)
    }

    public static func -= (lhs: inout UnitTime, rhs: UnitTime) {
        lhs = lhs - rhs
    }

    ///
    /// Multiplies a unit of time by an integer value.
    ///
    /// - Parameters:
    /// - lhs: The integer value to multiply.
    /// - rhs: The unit of time to multiply.
    /// - Returns: A `UnitTime` representing the result of multiplying the unit of time by the integer value.
    ///
    public static func * <T: BinaryInteger>(lhs: T, rhs: UnitTime) -> UnitTime {
        .init(saturating: Int64(clamping: lhs), perUnit: rhs.nanoseconds)
    }

    ///
    /// Multiplies a unit of time by an integer value.
    ///
    /// - Parameters:
    /// - lhs: The unit of time to multiply.
    /// - rhs: The integer value to multiply.
    /// - Returns: A `UnitTime` representing the result of multiplying the unit of time by the integer value.
    ///
    public static func * <T: BinaryInteger>(lhs: UnitTime, rhs: T) -> UnitTime {
        .init(saturating: Int64(clamping: rhs), perUnit: lhs.nanoseconds)
    }
}
