//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Date
import struct Foundation.Data
#endif

/// Encodes values into query items for use in URL requests.
///
/// ## Encoding happens in two passes
///
/// ``encode(_:forKey:)`` first walks the value and builds raw names and values, assembling
/// nested keys as it goes. It then percent encodes each name and each value on its own, before
/// anything is joined with `&` or `=`, which is why reserved characters inside a field are
/// escaped rather than treated as separators.
///
/// The space is deliberately left out of that pass and handled last, by
/// ``whitespaceEncodingStrategy``. Doing it in that order is what lets `+` stand for a space:
/// any literal `+` in the input is already `%2B` by then.
///
/// ## Thread safety
///
/// Every strategy is settable at any time, so the whole set is read once, under the lock, at
/// the top of ``encode(_:forKey:)``. Encoding then runs against that snapshot with no lock
/// held. Two consequences worth knowing: a strategy replaced part way through one call does not
/// take effect until the next, and encoding no longer serializes across threads.
public final class URLEncoder: @unchecked Sendable {

    // MARK: - Public properties

    /// The strategy for encoding dates.
    public var dateEncodingStrategy: DateEncodingStrategy {
        get { lock.withLock { _configuration.date } }
        set { lock.withLock { _configuration.date = newValue } }
    }

    /// The strategy for encoding keys.
    public var keyEncodingStrategy: KeyEncodingStrategy {
        get { lock.withLock { _configuration.key } }
        set { lock.withLock { _configuration.key = newValue } }
    }

    /// The strategy for encoding data.
    public var dataEncodingStrategy: DataEncodingStrategy {
        get { lock.withLock { _configuration.data } }
        set { lock.withLock { _configuration.data = newValue } }
    }

    /// The strategy for encoding booleans.
    public var boolEncodingStrategy: BoolEncodingStrategy {
        get { lock.withLock { _configuration.bool } }
        set { lock.withLock { _configuration.bool = newValue } }
    }

    /// The strategy for encoding optionals.
    public var optionalEncodingStrategy: OptionalEncodingStrategy {
        get { lock.withLock { _configuration.optional } }
        set { lock.withLock { _configuration.optional = newValue } }
    }

    /// The strategy for encoding arrays.
    public var arrayEncodingStrategy: ArrayEncodingStrategy {
        get { lock.withLock { _configuration.array } }
        set { lock.withLock { _configuration.array = newValue } }
    }

    /// The strategy for encoding dictionaries.
    public var dictionaryEncodingStrategy: DictionaryEncodingStrategy {
        get { lock.withLock { _configuration.dictionary } }
        set { lock.withLock { _configuration.dictionary = newValue } }
    }

    /// The strategy for encoding whitespace.
    public var whitespaceEncodingStrategy: WhitespaceEncodingStrategy {
        get { lock.withLock { _configuration.whitespace } }
        set { lock.withLock { _configuration.whitespace = newValue } }
    }

    // MARK: - Private properties

    private let lock = Lock()

    // MARK: - Unsafe properties

    private var _configuration = Configuration()

    // MARK: - Inits

    /// Initializes a new instance of `URLEncoder`.
    public init() {}

    // MARK: - Public methods

    /// Encodes the given value for the specified key into an array of query items.
    ///
    /// - Parameters:
    ///    - value: The value to encode. Dictionaries, arrays and optionals are walked
    ///    recursively; everything else goes through the matching strategy, or through string
    ///    interpolation when none applies.
    ///    - key: The key to associate with the value. Becomes the outermost component of every
    ///    nested name.
    ///
    /// - Returns: An array of query items, percent encoded and ready to join.
    ///
    /// - Throws: Whatever a strategy throws.
    public func encode(_ value: Any, forKey key: String) throws -> [QueryItem] {
        // Snapshot, then release. The lock used to be held across the whole recursion, which
        // meant it was held across calls into strategy code this type does not own. `Lock` is
        // not reentrant, so a strategy reading any of the public properties above deadlocked
        // the calling thread outright.
        let configuration = lock.withLock { _configuration }

        return try _encode(value, forKey: key, with: configuration)
    }

    // MARK: - Private methods

    private func _encode(
        _ value: Any,
        forKey key: String,
        with configuration: Configuration
    ) throws -> [QueryItem] {
        let items = try _recursiveEncode(
            value,
            forKey: key,
            with: configuration
        )
        .addingRFC3986PercentEncoding(withAllowedCharacters: { $0 == " " })

        let encoder = try encoder(for: configuration.whitespace)

        guard let whitespaceRepresentable = encoder.whitespaceRepresentable else {
            // Reports rather than passing the items through untouched.
            //
            // Only `.custom` can land here: `.percentEscaping` and `.plus` both set a
            // representation. A custom strategy that sets nothing leaves literal spaces in the
            // output, which is not valid in a URL, and returning them silently produced a
            // malformed request that failed somewhere much further downstream.
            throw URLEncoderError(.unsetWhitespaceRepresentable)
        }

        return items.replacingWhitespace(with: whitespaceRepresentable)
    }

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

    /// - Warning: Lockless, as the prefix says. It reads the strategies once on the way in and
    /// works from that copy, so a caller reaching for it directly gets whatever was configured
    /// at the moment of the call.
    func _recursiveEncode(_ value: Any, forKey key: String) throws -> [QueryItem] {
        try _recursiveEncode(
            value,
            forKey: key,
            with: lock.withLock { _configuration }
        )
    }

    /// - Warning: Lockless. Pure with respect to `configuration`, which is why it is safe to
    /// recurse through without holding anything.
    private func _recursiveEncode(
        _ value: Any,
        forKey key: String,
        with configuration: Configuration
    ) throws -> [QueryItem] {
        var queries = [QueryItem]()

        // Order matters. A dynamic cast unwraps optionals, so `Optional<Date>.some` matches
        // `as Date` here and only an actual `nil` falls through to `OptionalLiteral`.
        switch value {
        case let value as [String: Any]:
            try _appendDictionary(
                key: key,
                value: value,
                with: configuration,
                in: &queries
            )
        case let value as [Any]:
            try _appendArray(
                key: key,
                value: value,
                with: configuration,
                in: &queries
            )
        case let value as Date:
            try _appendDate(
                key: key,
                value: value,
                with: configuration,
                in: &queries
            )
        case let value as Bool:
            try _appendBool(
                key: key,
                value: value,
                with: configuration,
                in: &queries
            )
        case let value as Data:
            try _appendData(
                key: key,
                value: value,
                with: configuration,
                in: &queries
            )
        case let value as OptionalLiteral:
            try _appendOptional(
                key: key,
                value: value,
                with: configuration,
                in: &queries
            )
        default:
            try _appendDefault(
                key: key,
                value: value,
                with: configuration,
                in: &queries
            )
        }

        return queries
    }

    private func _appendDictionary(
        key: String,
        value: [String: Any],
        with configuration: Configuration,
        in items: inout [QueryItem]
    ) throws {
        let superKeyEncoder = try encoder(key, for: configuration.key)

        guard let superKey = try superKeyEncoder.getKey() else {
            return
        }

        // Sorted, because `Dictionary` iteration order is seeded per process and the query
        // string came out in a different order on every run. That made the output unusable for
        // anything that hashes or signs a URL, and made any test asserting on it flaky.
        for (key, value) in value.sorted(by: { $0.key < $1.key }) {
            let keyEncoder = try encoder(key, for: configuration.dictionary)

            if let key = try keyEncoder.getKey() {
                let queries = try _recursiveEncode(value, forKey: key, with: configuration)
                items.append(contentsOf: queries.appendingPrefixKey(superKey))
            }
        }
    }

    private func _appendArray(
        key: String,
        value: [Any],
        with configuration: Configuration,
        in items: inout [QueryItem]
    ) throws {
        let keyEncoder = try encoder(key, for: configuration.key)

        guard let key = try keyEncoder.getKey() else {
            return
        }

        for (index, value) in value.enumerated() {
            let indexEncoder = try encoder(index, for: configuration.array)

            if let indexKey = try indexEncoder.getKey() {
                let queries = try _recursiveEncode(value, forKey: indexKey, with: configuration)
                items.append(contentsOf: queries.appendingPrefixKey(key))
            }
        }
    }

    private func _appendDate(
        key: String,
        value: Date,
        with configuration: Configuration,
        in items: inout [QueryItem]
    ) throws {
        guard
            let queryItem = try encodeToQuery(
                key: encoder(key, for: configuration.key),
                value: encoder(value, for: configuration.date)
            )
        else { return }

        items.append(queryItem)
    }

    private func _appendBool(
        key: String,
        value: Bool,
        with configuration: Configuration,
        in items: inout [QueryItem]
    ) throws {
        guard
            let queryItem = try encodeToQuery(
                key: encoder(key, for: configuration.key),
                value: encoder(value, for: configuration.bool)
            )
        else { return }

        items.append(queryItem)
    }

    private func _appendData(
        key: String,
        value: Data,
        with configuration: Configuration,
        in items: inout [QueryItem]
    ) throws {
        guard
            let queryItem = try encodeToQuery(
                key: encoder(key, for: configuration.key),
                value: encoder(value, for: configuration.data)
            )
        else { return }

        items.append(queryItem)
    }

    private func _appendOptional(
        key: String,
        value: OptionalLiteral,
        with configuration: Configuration,
        in items: inout [QueryItem]
    ) throws {
        switch value.literal {
        case .some(let value):
            try items.append(contentsOf: _recursiveEncode(value, forKey: key, with: configuration))
        case .none:
            guard
                let queryItem = try encodeToQuery(
                    key: encoder(key, for: configuration.key),
                    value: encoder(for: configuration.optional)
                )
            else { return }

            items.append(queryItem)
        }
    }

    /// - Note: The fallback path. There is no value strategy for an arbitrary type, so this is
    /// `description` by way of interpolation, which for a type without a good one is a
    /// reflection dump.
    private func _appendDefault(
        key: String,
        value: Any,
        with configuration: Configuration,
        in items: inout [QueryItem]
    ) throws {
        let keyEncoder = try encoder(key, for: configuration.key)

        if let key = try keyEncoder.getKey() {
            items.append(
                .init(
                    name: key,
                    value: "\(value)"
                )
            )
        }
    }
}

// MARK: - Configuration

extension URLEncoder {

    /// Every strategy, as one value.
    ///
    /// Exists so the whole set can be read out of the lock in a single operation and passed
    /// down the recursion. Reading them one at a time would let a caller change one halfway
    /// through an encode and produce output that matches no configuration that ever existed.
    fileprivate struct Configuration {

        var date: DateEncodingStrategy = .iso8601
        var key: KeyEncodingStrategy = .literal
        var data: DataEncodingStrategy = .base64
        var bool: BoolEncodingStrategy = .literal
        var optional: OptionalEncodingStrategy = .literal
        var array: ArrayEncodingStrategy = .droppingIndex
        var dictionary: DictionaryEncodingStrategy = .subscripted
        var whitespace: WhitespaceEncodingStrategy = .percentEscaping
    }
}

// MARK: - OptionalLiteral

/// Lets `Optional` be recognised through an existential, which a dynamic cast cannot do without
/// knowing `Wrapped`.
///
/// - Note: No longer inherits `Sendable`. `Optional` is only conditionally `Sendable`, on
/// `Wrapped`, so an unconditional conformance to a `Sendable` protocol did not hold. Nothing
/// needed it either: this is used for one synchronous type test.
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
