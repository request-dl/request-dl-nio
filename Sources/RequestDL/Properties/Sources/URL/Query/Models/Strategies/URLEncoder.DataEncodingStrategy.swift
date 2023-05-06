/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    public enum DataEncodingStrategy: Sendable {

        case base64

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

