/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    /// Defines strategies for encoding dictionary key in a url encoded format
    public enum DictionaryEncodingStrategy: URLSingleEncodingStrategy {

        /// Encodes the dictionary key in square brackets with the key value inside, e.g. `[key]`.
        /// This is the default.
        case subscripted

        /// Encodes the dictionary key as a dot followed by the key value, e.g. `.key`.
        case accessMember

        /// Encodes the dictionary key using a custom closure that takes a `String` and an
        /// `Encoder` as input parameters and throws an error.
        case custom(@Sendable (String, Encoder) throws -> Void)

        // MARK: - Internal methods

        func encode(_ key: String, in encoder: URLEncoder.Encoder) throws {
            switch self {
            case .subscripted:
                try encodeSubscripted(key, in: encoder)
            case .accessMember:
                try encodeAccessMember(key, in: encoder)
            case .custom(let closure):
                try closure(key, encoder)
            }
        }

        // MARK: - Private methods

        private func encodeSubscripted(_ key: String, in encoder: URLEncoder.Encoder) throws {
            var container = encoder.keyContainer()
            try container.encode("[\(key)]")
        }

        private func encodeAccessMember(_ key: String, in encoder: URLEncoder.Encoder) throws {
            var container = encoder.keyContainer()
            try container.encode(".\(key)")
        }
    }
}
