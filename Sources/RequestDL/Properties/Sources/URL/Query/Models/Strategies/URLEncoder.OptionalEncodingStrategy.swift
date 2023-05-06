/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    public enum OptionalEncodingStrategy: Sendable {

        case droppingKey

        case droppingValue

        case literal

        case custom(@Sendable (Encoder) throws -> Void)
    }
}

extension URLEncoder.OptionalEncodingStrategy: URLEncodingStrategy {

    func encode(in encoder: URLEncoder.Encoder) throws {
        switch self {
        case .droppingKey:
            try encodeDroppingKey(in: encoder)
        case .droppingValue:
            try encodeDroppingValue(in: encoder)
        case .literal:
            try encodeLiteral(in: encoder)
        case .custom(let closure):
            try closure(encoder)
        }
    }
}

private extension URLEncoder.OptionalEncodingStrategy {

    func encodeDroppingKey(in encoder: URLEncoder.Encoder) throws {
        var container = encoder.valueContainer()
        try container.dropKey()
    }

    func encodeDroppingValue(in encoder: URLEncoder.Encoder) throws {
        var container = encoder.valueContainer()
        try container.encode("")
    }

    func encodeLiteral(in encoder: URLEncoder.Encoder) throws {
        var container = encoder.valueContainer()
        try container.encode("nil")
    }
}
