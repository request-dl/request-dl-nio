/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    public enum WhitespaceEncodingStrategy: Sendable {

        /// Replaces with %20
        case percentEscaping

        case plus

        case custom(@Sendable (URLEncoder.Encoder) throws -> Void)
    }
}

extension URLEncoder.WhitespaceEncodingStrategy: URLEncodingStrategy {

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
