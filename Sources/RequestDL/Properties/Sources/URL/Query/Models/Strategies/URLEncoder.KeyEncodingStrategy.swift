/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension URLEncoder {

    public enum KeyEncodingStrategy: Sendable {

        case literal

        case snakeCased

        case kebabCased

        case capitalized

        case uppercased

        case lowercased

        case custom(@Sendable (String, Encoder) throws -> Void)
    }
}

extension URLEncoder.KeyEncodingStrategy: URLSingleEncodingStrategy {

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
}

private extension URLEncoder.KeyEncodingStrategy {

    func encodeLiteral(_ key: String, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.keyContainer()
        try container.encode(key)
    }

    func encodeSnakeCased(_ key: String, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.keyContainer()

        try container.encode(key
            .splitByUppercasedCharacters()
            .joined(separator: "_")
            .lowercased()
        )
    }

    func encodeKebabCased(_ key: String, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.keyContainer()
        try container.encode(key
            .splitByUppercasedCharacters()
            .joined(separator: "-")
            .lowercased()
        )
    }

    func encodeCapitalized(_ key: String, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.keyContainer()

        var key = key
        if let index = key.firstIndex(where: { $0.isLetter }) {
            let uppercasedLetter = key[index].uppercased()
            key.replaceSubrange(index..<key.index(after: index), with: "\(uppercasedLetter)")
        }

        try container.encode(key)
    }

    func encodeUppercased(_ key: String, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.keyContainer()
        try container.encode(key.uppercased())
    }

    func encodeLowercased(_ key: String, in encoder: URLEncoder.Encoder) throws {
        var container = encoder.keyContainer()
        try container.encode(key.lowercased())
    }
}
