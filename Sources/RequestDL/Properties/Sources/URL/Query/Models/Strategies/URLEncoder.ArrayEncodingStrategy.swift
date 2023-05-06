/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    public enum ArrayEncodingStrategy: Sendable {

        /// Default. No index
        case droppingIndex

        /// Key [i]
        case subscripted

        /// Key .i
        case accessMember

        case custom(@Sendable (Int, URLEncoder.Encoder) throws -> Void)
    }
}

extension URLEncoder.ArrayEncodingStrategy: URLSingleEncodingStrategy {

    func encode(_ index: Int, in encoder: URLEncoder.Encoder) throws {
        switch self {
        case .droppingIndex:
            try encodeDroppingIndex(index, in: encoder)
        case .subscripted:
            try encodeSubscripted(index, in: encoder)
        case .accessMember:
            try encodeAccessMember(index, in: encoder)
        case .custom(let closure):
            try closure(index, encoder)
        }
    }
}

private extension URLEncoder.ArrayEncodingStrategy {

    func encodeDroppingIndex(_ index: Int, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.keyContainer()
        try container.encode("")
    }

    func encodeSubscripted(_ index: Int, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.keyContainer()
        try container.encode("[\(index)]")
    }

    func encodeAccessMember(_ index: Int, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.keyContainer()
        try container.encode(".\(index)")
    }
}
