/*
 See LICENSE for this package's licensing information.
*/

import Foundation

// Documentation:

/**
 An extension of `URLEncoder` that defines strategies for encoding non-optional values in a URL request.

 - `droppingKey`: Drops the key from the encoded string, leaving only the value.

 - `droppingValue`: Drops the value from the encoded string, leaving only the key.

 - `literal`:

 - `custom`:
 */
extension URLEncoder {

    /// Defines strategies for encoding none optional in a url encoded format
    public enum OptionalEncodingStrategy: Sendable {

        /// Drops the key and value from the encoded string, leaving no trace of it.
        case droppingKey

        /// Drops the value from the encoded string, leaving only the key. e.g. `key=`
        case droppingValue

        /// Encode value as "nil". This is the default.
        case literal

        /// Encodes the value using a custom closure that takes an `Encoder` as input parameter
        /// and throws an error.
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
