//
// See LICENSE for this package's licensing information.
//

extension URLEncoder {

    /// Defines strategies for encoding a `nil` in a url encoded format.
    ///
    /// Only reached for an optional that is actually empty. A `.some` is unwrapped and encoded
    /// through whichever strategy fits the value inside it.
    public enum OptionalEncodingStrategy: URLEncodingStrategy {

        /// Drops the key and the value, leaving no trace of the field.
        ///
        /// Dropping the value is what achieves this: a pair missing either half is not emitted.
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
            // Reads correctly now. It was `dropKey()`, which despite the name set the value,
            // so the line said the opposite of what it did while behaving as intended.
            try container.dropValue()
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
