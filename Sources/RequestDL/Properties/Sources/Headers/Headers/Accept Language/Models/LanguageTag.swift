//
// See LICENSE for this package's licensing information.
//

/// A BCP 47 language tag, such as `"en"`, `"en-US"` or `"pt-BR"`.
///
/// Used to specify one entry of an ``AcceptLanguageHeader``. Unlike ``ContentType`` or
/// ``Charset``, there is no static registry of known values here: languages are open-ended,
/// so every `LanguageTag` comes from a string.
///
/// ```swift
/// let languageTag: LanguageTag = "pt-BR"
/// ```
public struct LanguageTag: Sendable, Hashable {

    // MARK: - Internal properties

    let rawValue: String

    // MARK: - Inits

    ///
    /// Initializes a `LanguageTag` instance with a given string value.
    ///
    /// - Parameter rawValue: The BCP 47 language tag, e.g. `"en"`, `"en-US"`, `"pt-BR"`.
    ///
    public init<S: StringProtocol>(_ rawValue: S) {
        self.rawValue = String(rawValue)
    }
}

// MARK: - ExpressibleByStringLiteral

extension LanguageTag: ExpressibleByStringLiteral {

    ///
    /// Initializes a `LanguageTag` instance using a string literal.
    ///
    /// - Parameter value: A string literal representing the language tag.
    ///
    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

// MARK: - LosslessStringConvertible

extension LanguageTag: LosslessStringConvertible {

    public var description: String {
        rawValue
    }
}
