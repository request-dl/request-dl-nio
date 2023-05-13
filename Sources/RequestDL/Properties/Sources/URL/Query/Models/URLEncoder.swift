/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/// A class that encodes values into query items for use in URL requests.
public final class URLEncoder: @unchecked Sendable {

    // MARK: - Public properties

    /// The strategy for encoding dates.
    public var dateEncodingStrategy: DateEncodingStrategy {
        get { lock.withLock { _dateEncodingStrategy } }
        set { lock.withLock { _dateEncodingStrategy = newValue } }
    }

    /// The strategy for encoding keys.
    public var keyEncodingStrategy: KeyEncodingStrategy {
        get { lock.withLock { _keyEncodingStrategy } }
        set { lock.withLock { _keyEncodingStrategy = newValue } }
    }

    /// The strategy for encoding data.
    public var dataEncodingStrategy: DataEncodingStrategy {
        get { lock.withLock { _dataEncodingStrategy } }
        set { lock.withLock { _dataEncodingStrategy = newValue } }
    }

    /// The strategy for encoding booleans.
    public var boolEncodingStrategy: BoolEncodingStrategy {
        get { lock.withLock { _boolEncodingStrategy } }
        set { lock.withLock { _boolEncodingStrategy = newValue } }
    }

    /// The strategy for encoding optionals.
    public var optionalEncodingStrategy: OptionalEncodingStrategy {
        get { lock.withLock { _optionalEncodingStrategy } }
        set { lock.withLock { _optionalEncodingStrategy = newValue } }
    }

    /// The strategy for encoding arrays.
    public var arrayEncodingStrategy: ArrayEncodingStrategy {
        get { lock.withLock { _arrayEncodingStrategy } }
        set { lock.withLock { _arrayEncodingStrategy = newValue } }
    }

    /// The strategy for encoding dictionaries.
    public var dictionaryEncodingStrategy: DictionaryEncodingStrategy {
        get { lock.withLock { _dictionaryEncodingStrategy } }
        set { lock.withLock { _dictionaryEncodingStrategy = newValue } }
    }

    /// The strategy for encoding whitespace.
    public var whitespaceEncodingStrategy: WhitespaceEncodingStrategy {
        get { lock.withLock { _whitespaceEncodingStrategy } }
        set { lock.withLock { _whitespaceEncodingStrategy = newValue } }
    }

    // MARK: - Private properties

    private let lock = Lock()

    // MARK: - Unsafe properties

    private var _dateEncodingStrategy: DateEncodingStrategy = .iso8601

    private var _keyEncodingStrategy: KeyEncodingStrategy = .literal

    private var _dataEncodingStrategy: DataEncodingStrategy = .base64

    private var _boolEncodingStrategy: BoolEncodingStrategy = .literal

    private var _optionalEncodingStrategy: OptionalEncodingStrategy = .literal

    private var _arrayEncodingStrategy: ArrayEncodingStrategy = .droppingIndex

    private var _dictionaryEncodingStrategy: DictionaryEncodingStrategy = .subscripted

    private var _whitespaceEncodingStrategy: WhitespaceEncodingStrategy = .percentEscaping

    // MARK: - Inits

    /// Initializes a new instance of `URLEncoder`.
    public init() {}

    // MARK: - Public properties

    /**
     Encodes the given value for the specified key into an array of query items.

     - Parameters:
        - value: The value to encode.
        - key: The key to associate with the value.

     - Returns: An array of query items representing the encoded value and key.

     - Throws: An error if encoding fails.
     */
    public func encode(_ value: Any, forKey key: String) throws -> [QueryItem] {
        try lock.withLock {
            let items = try _recursiveEncode(value, forKey: key).addingRFC3986PercentEncoding(
                withAllowedCharacters: .init(charactersIn: " ")
            )

            let encoder = try encoder(for: _whitespaceEncodingStrategy)

            if let whitespaceRepresentable = encoder.whitespaceRepresentable {
                return items.replacingWhitespace(with: whitespaceRepresentable)
            } else {
                return items
            }
        }
    }

    // MARK: - Private methods

    private func encodeToQuery(
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

    private func encoder<Strategy: URLSingleEncodingStrategy>(
        _ value: Strategy.Value,
        for strategy: Strategy
    ) throws -> Encoder {
        let encoder = Encoder()
        try strategy.encode(value, in: encoder)
        return encoder
    }

    private func encoder<Strategy: URLEncodingStrategy>(for strategy: Strategy) throws -> Encoder {
        let encoder = Encoder()
        try strategy.encode(in: encoder)
        return encoder
    }

    // MARK: - Unsafe methods

    func _recursiveEncode(_ value: Any, forKey key: String) throws -> [QueryItem] {
        var queries = [QueryItem]()

        switch value {
        case let value as [String: Any]:
            try _appendDictionary(
                key: key,
                value: value,
                in: &queries
            )
        case let value as [Any]:
            try _appendArray(
                key: key,
                value: value,
                in: &queries
            )
        case let value as Date:
            try _appendDate(
                key: key,
                value: value,
                in: &queries
            )
        case let value as Bool:
            try _appendBool(
                key: key,
                value: value,
                in: &queries
            )
        case let value as Data:
            try _appendData(
                key: key,
                value: value,
                in: &queries
            )
        case let value as OptionalLiteral:
            try _appendOptional(
                key: key,
                value: value,
                in: &queries
            )
        default:
            try _appendDefault(
                key: key,
                value: value,
                in: &queries
            )
        }

        return queries
    }

    private func _appendDictionary(
        key: String,
        value: [String: Any],
        in items: inout [QueryItem]
    ) throws {
        let superKeyEncoder = try encoder(key, for: _keyEncodingStrategy)

        guard let superKey = try superKeyEncoder.getKey() else {
            return
        }

        for (key, value) in value {
            let keyEncoder = try encoder(key, for: _dictionaryEncodingStrategy)

            if let key = try keyEncoder.getKey() {
                let queries = try _recursiveEncode(value, forKey: key)
                items.append(contentsOf: queries.appendingPrefixKey(superKey))
            }
        }
    }

    private func _appendArray(
        key: String,
        value: [Any],
        in items: inout [QueryItem]
    ) throws {
        let keyEncoder = try encoder(key, for: _keyEncodingStrategy)

        guard let key = try keyEncoder.getKey() else {
            return
        }

        for (index, value) in value.enumerated() {
            let indexEncoder = try encoder(index, for: _arrayEncodingStrategy)

            if let indexKey = try indexEncoder.getKey() {
                let queries = try _recursiveEncode(value, forKey: indexKey)
                items.append(contentsOf: queries.appendingPrefixKey(key))
            }
        }
    }

    private func _appendDate(
        key: String,
        value: Date,
        in items: inout [QueryItem]
    ) throws {
        guard let queryItem = try encodeToQuery(
            key: encoder(key, for: _keyEncodingStrategy),
            value: encoder(value, for: _dateEncodingStrategy)
        ) else { return }

        items.append(queryItem)
    }

    private func _appendBool(
        key: String,
        value: Bool,
        in items: inout [QueryItem]
    ) throws {
        guard let queryItem = try encodeToQuery(
            key: encoder(key, for: _keyEncodingStrategy),
            value: encoder(value, for: _boolEncodingStrategy)
        ) else { return }

        items.append(queryItem)
    }

    private func _appendData(
        key: String,
        value: Data,
        in items: inout [QueryItem]
    ) throws {
        guard let queryItem = try encodeToQuery(
            key: encoder(key, for: _keyEncodingStrategy),
            value: encoder(value, for: _dataEncodingStrategy)
        ) else { return }

        items.append(queryItem)
    }

    private func _appendOptional(
        key: String,
        value: OptionalLiteral,
        in items: inout [QueryItem]
    ) throws {
        switch value.literal {
        case .some(let value):
            try items.append(contentsOf: _recursiveEncode(value, forKey: key))
        case .none:
            guard let queryItem = try encodeToQuery(
                key: encoder(key, for: _keyEncodingStrategy),
                value: encoder(for: _optionalEncodingStrategy)
            ) else { return }

            items.append(queryItem)
        }
    }

    private func _appendDefault(
        key: String,
        value: Any,
        in items: inout [QueryItem]
    ) throws {
        let keyEncoder = try encoder(key, for: _keyEncodingStrategy)

        if let key = try keyEncoder.getKey() {
            items.append(.init(
                name: key,
                value: "\(value)"
            ))
        }
    }
}

private protocol OptionalLiteral: Sendable {

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
