//
// See LICENSE for this package's licensing information.
//

/// A single `name=value` pair in a URL query, or a bare `name`.
public struct QueryItem: Sendable, Hashable {

    // MARK: - Public properties

    /// The name of the query item.
    ///
    /// - Important: Percent encoded once it has been through ``URLEncoder``, and raw before
    /// that. The type does not track which, so do not encode a value twice by hand.
    public let name: String

    /// The value associated with the query item.
    ///
    /// - Important: Same encoding caveat as ``name``.
    public let value: String

    /// Whether the item was written with a value, as in `name=value` or `name=`, and not as a
    /// bare `name`.
    ///
    /// A bare name (`?uploads`, `?thumbnail&sig=abc`) is a different query from `name=`: a
    /// server can read the flag by its presence alone, and a signed URL signs the exact bytes.
    /// ``value`` is empty for a bare name.
    public let hasValue: Bool

    // MARK: - Inits

    /// - Note: New in 4.0. The implicit memberwise initializer of a public struct is internal,
    /// so nothing outside the package could construct one of these, despite the type and both
    /// of its properties being public.
    public init(name: String, value: String) {
        self.init(name: name, value: value, hasValue: true)
    }

    /// Creates a bare `name`, rendered without `=`.
    public init(name: String) {
        self.init(name: name, value: "", hasValue: false)
    }

    init(name: String, value: String, hasValue: Bool) {
        self.name = name
        self.value = value
        self.hasValue = hasValue
    }
}

// MARK: - [QueryItem] extension

extension [QueryItem] {

    /// Prefixes every name, which is how a nested key is assembled.
    ///
    /// The caller supplies the separator as part of `key`, so `"user"` and `"[name]"` become
    /// `"user[name]"`, and the array and dictionary strategies decide the bracket style.
    func appendingPrefixKey(_ key: String) -> [QueryItem] {
        map {
            .init(
                name: key + $0.name,
                value: $0.value,
                hasValue: $0.hasValue
            )
        }
    }

    /// Percent encodes every name and value independently.
    ///
    /// Independently is the point. Encoding is applied per field, before anything is joined
    /// with `&` and `=`, so the narrow set in ``Swift/Character/isRFC3986QueryAllowed`` is
    /// correct here: a `&` inside a value has to become `%26` precisely because it is not a
    /// separator yet.
    func addingRFC3986PercentEncoding(
        withAllowedCharacters allowedCharacters: (Character) -> Bool = { _ in false }
    ) -> [QueryItem] {
        map {
            .init(
                name: $0.name.addingRFC3986PercentEncoding(withAllowedCharacters: allowedCharacters),
                value: $0.value.addingRFC3986PercentEncoding(withAllowedCharacters: allowedCharacters),
                hasValue: $0.hasValue
            )
        }
    }

    /// Substitutes every space with `representable`.
    ///
    /// Runs after percent encoding, and that ordering is what makes `+` as a space marker safe:
    /// a literal `+` in the input has already become `%2B` by the time this puts unencoded `+`
    /// characters in, so the two can never be confused on the way back.
    ///
    /// - Note: Built on `split` and `joined` rather than `replacing(_:with:)` or Foundation's
    /// `replacingOccurrences(of:with:)`: the former needs macOS 13, and the latter is the
    /// Foundation dependency this package is trying to shed. `omittingEmptySubsequences: false`
    /// is what keeps runs of spaces, and leading and trailing ones, intact.
    func replacingWhitespace(with representable: String) -> [QueryItem] {
        map {
            .init(
                name: $0.name.replacingWhitespace(with: representable),
                value: $0.value.replacingWhitespace(with: representable),
                hasValue: $0.hasValue
            )
        }
    }

    /// Renders as a query string, without the leading `?`.
    func joined() -> String {
        map { $0.hasValue ? "\($0.name)=\($0.value)" : $0.name }
            .joined(separator: "&")
    }
}

// MARK: - String extension

extension String {

    fileprivate func replacingWhitespace(with representable: String) -> String {
        split(separator: " ", omittingEmptySubsequences: false)
            .joined(separator: representable)
    }
}
