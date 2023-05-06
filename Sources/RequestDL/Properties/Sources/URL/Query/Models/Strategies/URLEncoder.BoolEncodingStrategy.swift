/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    public enum BoolEncodingStrategy: Sendable {

        case literal

        case numeric

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
