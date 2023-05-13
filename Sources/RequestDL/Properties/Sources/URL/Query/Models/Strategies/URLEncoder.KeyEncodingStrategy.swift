/*
 See LICENSE for this package's licensing information.
 */

import Foundation

extension URLEncoder {

    /// Defines strategies for encoding key in a url encoded format
    public enum KeyEncodingStrategy: URLSingleEncodingStrategy {

        /// Uses the key as is. This is the default.
        case literal

        /// Encodes the key in snake case format, e.g. "key_name".
        case snakeCased

        /// Encodes the key in kebab case format, e.g. "key-name".
        case kebabCased

        /// Capitalizes the first letter of the key, e.g. "KeyName".
        case capitalized

        /// Encodes the key in all uppercase format, e.g. "KEYNAME".
        case uppercased

        /// Encodes the key in all lowercase format, e.g. "keyname".
        case lowercased

        /// Encodes the key using a custom closure that takes a `String` and an `Encoder`
        /// as input parameters and throws an error.
        case custom(@Sendable (String, Encoder) throws -> Void)

        // MARK: - Internal methods

        func encode(_ key: String, in encoder: URLEncoder.Encoder) throws {
            switch self {
            case .literal:
                try encodeLiteral(key, in: encoder)
            case .snakeCased:
                try encodeSnakeCased(key, in: encoder)
            case .kebabCased:
                try encodeKebabCased(key, in: encoder)
            case .capitalized:
                try encodeCapitalized(key, in: encoder)
            case .uppercased:
                try encodeUppercased(key, in: encoder)
            case .lowercased:
                try encodeLowercased(key, in: encoder)
            case .custom(let closure):
                try closure(key, encoder)
            }
        }

        // MARK: - Private methods

        private func encodeLiteral(_ key: String, in encoder: URLEncoder.Encoder) throws {
            var container = encoder.keyContainer()
            try container.encode(key)
        }

        private func encodeSnakeCased(_ key: String, in encoder: URLEncoder.Encoder) throws {
            var container = encoder.keyContainer()

            try container.encode(key
                .splitByUppercasedCharacters()
                .joined(separator: "_")
                .lowercased()
            )
        }

        private func encodeKebabCased(_ key: String, in encoder: URLEncoder.Encoder) throws {
            var container = encoder.keyContainer()
            try container.encode(key
                .splitByUppercasedCharacters()
                .joined(separator: "-")
                .lowercased()
            )
        }

        private func encodeCapitalized(_ key: String, in encoder: URLEncoder.Encoder) throws {
            var container = encoder.keyContainer()

            var key = key
            if let index = key.firstIndex(where: { $0.isLetter }) {
                let uppercasedLetter = key[index].uppercased()
                key.replaceSubrange(index..<key.index(after: index), with: uppercasedLetter)
            }

            try container.encode(key)
        }

        private func encodeUppercased(_ key: String, in encoder: URLEncoder.Encoder) throws {
            var container = encoder.keyContainer()
            try container.encode(key.uppercased())
        }

        private func encodeLowercased(_ key: String, in encoder: URLEncoder.Encoder) throws {
            var container = encoder.keyContainer()
            try container.encode(key.lowercased())
        }
    }
}
