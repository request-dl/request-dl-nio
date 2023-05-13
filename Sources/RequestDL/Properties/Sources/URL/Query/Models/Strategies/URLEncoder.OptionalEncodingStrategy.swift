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
    public enum OptionalEncodingStrategy: URLEncodingStrategy {

        /// Drops the key and value from the encoded string, leaving no trace of it.
        case droppingKey

        /// Drops the value from the encoded string, leaving only the key. e.g. `key=`
        case droppingValue

        /// Encode value as "nil". This is the default.
        case literal

        /// Encodes the value using a custom closure that takes an `Encoder` as input parameter
        /// and throws an error.
        case custom(@Sendable (Encoder) throws -> Void)

        // MARK: - Internal methods

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

        // MARK: - Private methods

        private func encodeDroppingKey(in encoder: URLEncoder.Encoder) throws {
            var container = encoder.valueContainer()
            try container.dropKey()
        }

        private func encodeDroppingValue(in encoder: URLEncoder.Encoder) throws {
            var container = encoder.valueContainer()
            try container.encode("")
        }

        private func encodeLiteral(in encoder: URLEncoder.Encoder) throws {
            var container = encoder.valueContainer()
            try container.encode("nil")
        }
    }
}
