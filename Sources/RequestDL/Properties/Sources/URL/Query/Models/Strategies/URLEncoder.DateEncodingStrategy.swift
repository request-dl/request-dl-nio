/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

extension URLEncoder {

    /// Defines strategies for encoding dates in a url encoded format
    public enum DateEncodingStrategy: Sendable {

        /// Encodes the date as the number of seconds since January 1, 1970, as a `Double`.
        case secondsSince1970

        /// Encodes the date as the number of milliseconds since January 1, 1970, as a `Int`.
        case millisecondsSince1970

        /// Encodes the date as an ISO8601-formatted string. This is the default.
        case iso8601

        /// Encodes the date using a given `DateFormatter` instance.
        case formatter(DateFormatter)

        /// Encodes the date using a custom closure that takes a `Date` and an `Encoder`
        /// as input parameters and throws an error.
        case custom(@Sendable (Date, Encoder) throws -> Void)
    }
}

extension URLEncoder.DateEncodingStrategy: URLSingleEncodingStrategy {

    func encode(_ date: Date, in encoder: URLEncoder.Encoder) throws {
        switch self {
        case .secondsSince1970:
            try encodeSecondsSince1970(date, in: encoder)
        case .millisecondsSince1970:
            try encodeMillisecondsSince1970(date, in: encoder)
        case .iso8601:
            try encodeISO8601(date, in: encoder)
        case .formatter(let dateFormatter):
            try encodeDateFormatter(date, in: encoder, with: dateFormatter)
        case .custom(let closure):
            try closure(date, encoder)
        }
    }
}

private extension URLEncoder.DateEncodingStrategy {

    func encodeSecondsSince1970(_ date: Date, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.valueContainer()
        try container.encode("\(Int64(date.timeIntervalSince1970))")
    }

    func encodeMillisecondsSince1970(_ date: Date, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.valueContainer()
        try container.encode("\(Int64(date.timeIntervalSince1970) * 1_000)")
    }

    func encodeISO8601(_ date: Date, in encoder: URLEncoder.Encoder) throws {
        let dateFormatter = ISO8601DateFormatter()

        var container = encoder.valueContainer()
        try container.encode(dateFormatter.string(from: date))
    }

    func encodeDateFormatter(
        _ date: Date,
        in encoder: URLEncoder.Encoder,
        with dateFormatter: DateFormatter
    ) throws {
        var container = encoder.valueContainer()
        try container.encode(dateFormatter.string(from: date))
    }
}
