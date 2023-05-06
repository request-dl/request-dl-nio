/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    /// Defines strategies for encoding boolean in a url encoded format
    public enum BoolEncodingStrategy: Sendable {

        /// Encodes the boolean value using the literal strings "true" or "false". This is the default.
        case literal

        /// Encodes the boolean value using the integers 1 or 0, respectively.
        case numeric

        /// Encodes the boolean value using a custom closure that takes a `Bool` and an `Encoder`
        /// as input parameters and throws an error.
        case custom(@Sendable (Bool, Encoder) throws -> Void)
    }
}

extension URLEncoder.BoolEncodingStrategy: URLSingleEncodingStrategy {

    func encode(_ flag: Bool, in encoder: URLEncoder.Encoder) throws {
        switch self {
        case .literal:
            try encodeLiteral(flag, in: encoder)
        case .numeric:
            try encodeNumeric(flag, in: encoder)
        case .custom(let closure):
            try closure(flag, encoder)
        }
    }
}

private extension URLEncoder.BoolEncodingStrategy {

    func encodeLiteral(_ flag: Bool, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.valueContainer()

        if flag {
            try container.encode("true")
        } else {
            try container.encode("false")
        }
    }

    func encodeNumeric(_ flag: Bool, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.valueContainer()

        if flag {
            try container.encode("1")
        } else {
            try container.encode("0")
        }
    }
}
