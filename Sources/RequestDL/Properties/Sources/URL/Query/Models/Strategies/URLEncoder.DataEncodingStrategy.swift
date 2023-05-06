/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    /// Defines strategies for encoding data in a url encoded format
    public enum DataEncodingStrategy: Sendable {

        /// Encodes the data as a Base64-encoded string. This is the default.
        case base64

        /// Encodes the data using a custom closure that takes a `Data` and an `Encoder` as input
        /// parameters and throws an error.
        case custom(@Sendable (Data, Encoder) throws -> Void)
    }
}

extension URLEncoder.DataEncodingStrategy: URLSingleEncodingStrategy {

    func encode(_ data: Data, in encoder: URLEncoder.Encoder) throws {
        switch self {
        case .base64:
            try encodeBase64(data, in: encoder)
        case .custom(let closure):
            try closure(data, encoder)
        }
    }
}

private extension URLEncoder.DataEncodingStrategy {

    func encodeBase64(_ data: Data, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.valueContainer()
        try container.encode(data.base64EncodedString())
    }
}
