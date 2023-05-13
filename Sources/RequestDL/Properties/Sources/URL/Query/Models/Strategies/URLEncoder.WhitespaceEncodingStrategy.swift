/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    /// Defines strategies for encoding whitespace in a url encoded format
    public enum WhitespaceEncodingStrategy: URLEncodingStrategy {

        /// Replaces whitespace with `%20`.
        case percentEscaping

        /// Replaces whitespace with `+`.
        case plus

        /// Encodes whitespace using a custom closure that takes an `Encoder` as input parameter
        /// and throws an error.
        case custom(@Sendable (URLEncoder.Encoder) throws -> Void)

        // MARK: - Internal methods

        func encode(in encoder: URLEncoder.Encoder) throws {
            switch self {
            case .percentEscaping:
                encoder.whitespaceRepresentable = "%20"
            case .plus:
                encoder.whitespaceRepresentable = "+"
            case .custom(let closure):
                try closure(encoder)
            }
        }
    }
}
