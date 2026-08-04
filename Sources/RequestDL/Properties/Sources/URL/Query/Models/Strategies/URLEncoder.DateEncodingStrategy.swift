//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
#endif

extension URLEncoder {

    /// Defines strategies for encoding dates in a url encoded format
    public enum DateEncodingStrategy: URLSingleEncodingStrategy {

        /// Encodes the date as the number of seconds since January 1, 1970, as a `String`.
        case secondsSince1970

        /// Encodes the date as the number of milliseconds since January 1, 1970, as a `String`.
        case millisecondsSince1970

        /// Encodes the date as an ISO8601-formatted string (UTC). This is the default.
        case iso8601

        /// Encodes the date using a custom closure that takes a `Date` and returns a formatted
        /// `String`.
        ///
        /// - Note: Replaces the `formatter(DateFormatter)` case of 3.x. `DateFormatter` is not
        /// part of `FoundationEssentials`, so a strategy holding one could not exist off Apple.
        /// A closure lets the caller reach for whatever formatter their platform does have.
        case custom(@Sendable (Date) throws -> String)

        // MARK: - Internal methods

        func encode(_ date: Date, in encoder: URLEncoder.Encoder) throws {
            switch self {
            case .secondsSince1970:
                try encodeSecondsSince1970(date, in: encoder)
            case .millisecondsSince1970:
                try encodeMillisecondsSince1970(date, in: encoder)
            case .iso8601:
                try encodeISO8601(date, in: encoder)
            case .custom(let closure):
                var container = encoder.valueContainer()
                try container.encode(try closure(date))
            }
        }

        // MARK: - Private methods

        /// - Note: Floors rather than truncating. `Int64(-0.5)` is zero, which places a moment
        /// just before the epoch on the wrong side of it.
        private func encodeSecondsSince1970(_ date: Date, in encoder: URLEncoder.Encoder) throws {
            var container = encoder.valueContainer()
            try container.encode("\(Int64(date.timeIntervalSince1970.rounded(.down)))")
        }

        /// - Note: Same flooring caveat as ``encodeSecondsSince1970(_:in:)``.
        private func encodeMillisecondsSince1970(_ date: Date, in encoder: URLEncoder.Encoder) throws {
            var container = encoder.valueContainer()
            try container.encode("\(Int64((date.timeIntervalSince1970 * 1000).rounded(.down)))")
        }

        /// - Important: Formatting must go through ``Internals/GregorianCalendar``, shared with
        /// the HTTP date parsing the cache layer needs, rather than a private copy in this file
        /// — a year count done by looping is wrong for anything before 1970.
        private func encodeISO8601(_ date: Date, in encoder: URLEncoder.Encoder) throws {
            var container = encoder.valueContainer()
            try container.encode(date.toISO8601String())
        }
    }
}
