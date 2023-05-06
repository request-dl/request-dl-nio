/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A class that encodes values into query items for use in URL requests.
public class URLEncoder {

    /// The strategy for encoding dates.
    public var dateEncodingStrategy: DateEncodingStrategy = .iso8601

    /// The strategy for encoding keys.
    public var keyEncodingStrategy: KeyEncodingStrategy = .literal

    /// The strategy for encoding data.
    public var dataEncodingStrategy: DataEncodingStrategy = .base64

    /// The strategy for encoding booleans.
    public var boolEncodingStrategy: BoolEncodingStrategy = .literal

    /// The strategy for encoding optionals.
    public var optionalEncodingStrategy: OptionalEncodingStrategy = .literal

    /// The strategy for encoding arrays.
    public var arrayEncodingStrategy: ArrayEncodingStrategy = .droppingIndex

    /// The strategy for encoding dictionaries.
    public var dictionaryEncodingStrategy: DictionaryEncodingStrategy = .subscripted

    /// The strategy for encoding whitespace.
    public var whitespaceEncodingStrategy: WhitespaceEncodingStrategy = .percentEscaping

    /// Initializes a new instance of `URLEncoder`.
    public init() {}
}

extension URLEncoder {

    /**
     Encodes the given value for the specified key into an array of query items.

     - Parameters:
        - value: The value to encode.
        - key: The key to associate with the value.

     - Returns: An array of query items representing the encoded value and key.

     - Throws: An error if encoding fails.
     */
    public func encode(_ value: Any, forKey key: String) throws -> [QueryItem] {
        let items = try recursiveEncode(value, forKey: key).addingRFC3986PercentEncoding(
            withAllowedCharacters: .init(charactersIn: " ")
        )

        let encoder = try encoder(for: whitespaceEncodingStrategy)

        if let whitespaceRepresentable = encoder.whitespaceRepresentable {
            return items.replacingWhitespace(with: whitespaceRepresentable)
        } else {
            return items
        }
    }
}

private extension URLEncoder {

    func encoder<Strategy: URLSingleEncodingStrategy>(
        _ value: Strategy.Value,
        for strategy: Strategy
    ) throws -> Encoder {
        let encoder = Encoder()
        try strategy.encode(value, in: encoder)
        return encoder
    }

    func encoder<Strategy: URLEncodingStrategy>(for strategy: Strategy) throws -> Encoder {
        let encoder = Encoder()
        try strategy.encode(in: encoder)
        return encoder
    }

    func encodeToQuery(
        key: Encoder,
        value: Encoder
    ) throws -> QueryItem? {
        guard
            let key = try key.getKey(),
            let value = try value.getValue()
        else { return nil }

        return .init(
            name: key,
            value: value
        )
    }
}

public extension URLEncoder {

    private func appendDictionary(
        key: String,
        value: [String: Any],
        in items: inout [QueryItem]
    ) throws {
        let superKeyEncoder = try encoder(key, for: keyEncodingStrategy)

        guard let superKey = try superKeyEncoder.getKey() else {
            return
        }

        for (key, value) in value {
            let keyEncoder = try encoder(key, for: dictionaryEncodingStrategy)

            if let key = try keyEncoder.getKey() {
                let queries = try recursiveEncode(value, forKey: key)
                items.append(contentsOf: queries.appendingPrefixKey(superKey))
            }
        }
    }

    private func appendArray(
        key: String,
        value: [Any],
        in items: inout [QueryItem]
    ) throws {
        let keyEncoder = try encoder(key, for: keyEncodingStrategy)

        guard let key = try keyEncoder.getKey() else {
            return
        }

        for (index, value) in value.enumerated() {
            let indexEncoder = try encoder(index, for: arrayEncodingStrategy)

            if let indexKey = try indexEncoder.getKey() {
                let queries = try recursiveEncode(value, forKey: indexKey)
                items.append(contentsOf: queries.appendingPrefixKey(key))
            }
        }
    }

    private func appendDate(
        key: String,
        value: Date,
        in items: inout [QueryItem]
    ) throws {
        guard let queryItem = try encodeToQuery(
            key: encoder(key, for: keyEncodingStrategy),
            value: encoder(value, for: dateEncodingStrategy)
        ) else { return }

        items.append(queryItem)
    }

    private func appendBool(
        key: String,
        value: Bool,
        in items: inout [QueryItem]
    ) throws {
        guard let queryItem = try encodeToQuery(
            key: encoder(key, for: keyEncodingStrategy),
            value: encoder(value, for: boolEncodingStrategy)
        ) else { return }

        items.append(queryItem)
    }

    private func appendData(
        key: String,
        value: Data,
        in items: inout [QueryItem]
    ) throws {
        guard let queryItem = try encodeToQuery(
            key: encoder(key, for: keyEncodingStrategy),
            value: encoder(value, for: dataEncodingStrategy)
        ) else { return }

        items.append(queryItem)
    }

    private func appendOptional(
        key: String,
        value: OptionalLiteral,
        in items: inout [QueryItem]
    ) throws {
        switch value.literal {
        case .some(let value):
            try items.append(contentsOf: recursiveEncode(value, forKey: key))
        case .none:
            guard let queryItem = try encodeToQuery(
                key: encoder(key, for: keyEncodingStrategy),
                value: encoder(for: optionalEncodingStrategy)
            ) else { return }

            items.append(queryItem)
        }
    }

    private func appendDefault(
        key: String,
        value: Any,
        in items: inout [QueryItem]
    ) throws {
        let keyEncoder = try encoder(key, for: keyEncodingStrategy)

        if let key = try keyEncoder.getKey() {
            items.append(.init(
                name: key,
                value: "\(value)"
            ))
        }
    }

    func recursiveEncode(_ value: Any, forKey key: String) throws -> [QueryItem] {
        var queries = [QueryItem]()

        switch value {
        case let value as [String: Any]:
            try appendDictionary(
                key: key,
                value: value,
                in: &queries
            )
        case let value as [Any]:
            try appendArray(
                key: key,
                value: value,
                in: &queries
            )
        case let value as Date:
            try appendDate(
                key: key,
                value: value,
                in: &queries
            )
        case let value as Bool:
            try appendBool(
                key: key,
                value: value,
                in: &queries
            )
        case let value as Data:
            try appendData(
                key: key,
                value: value,
                in: &queries
            )
        case let value as OptionalLiteral:
            try appendOptional(
                key: key,
                value: value,
                in: &queries
            )
        default:
            try appendDefault(
                key: key,
                value: value,
                in: &queries
            )
        }

        return queries
    }
}

private protocol OptionalLiteral {

    var literal: Any? { get }
}

extension Optional: OptionalLiteral {

    fileprivate var literal: Any? {
        switch self {
        case .some(let wrapped):
            return wrapped
        case .none:
            return nil
        }
    }
}
