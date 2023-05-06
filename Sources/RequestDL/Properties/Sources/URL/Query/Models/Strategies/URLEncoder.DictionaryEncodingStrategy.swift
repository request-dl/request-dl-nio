/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    public enum DictionaryEncodingStrategy: Sendable {

        /// [key]
        case subscripted

        /// .key
        case accessMember

        case custom(@Sendable (String, Encoder) throws -> Void)
    }
}

extension URLEncoder.DictionaryEncodingStrategy: URLSingleEncodingStrategy {

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
}

private extension URLEncoder.DictionaryEncodingStrategy {

    func encodeSubscripted(_ key: String, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.keyContainer()
        try container.encode("[\(key)]")
    }

    func encodeAccessMember(_ key: String, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.keyContainer()
        try container.encode(".\(key)")
    }
}

