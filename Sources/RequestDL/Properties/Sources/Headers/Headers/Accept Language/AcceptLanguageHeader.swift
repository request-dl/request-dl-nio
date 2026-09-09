//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(Darwin)
import struct Foundation.Locale
#endif

/// Sets the `Accept-Language` header in the request.
///
/// ``RequestDL/AcceptLanguageHeader`` provides two ways to build the header value:
///
/// - An explicit, ordered list of ``LanguageTag``s, most preferred first:
///
/// ```swift
/// AcceptLanguageHeader("pt-BR", "en-US")
/// ```
///
/// - On Darwin, the system's preferred languages (`Locale.preferredLanguages`), via the empty
/// initializer ``RequestDL/AcceptLanguageHeader/init()``. This is a separate, opt-in
/// initializer rather than something applied implicitly: not every app should track the
/// system's language — one that pins its own in-app language regardless of Settings has no use
/// for it.
///
/// Either way, each language is assigned a descending `q` weight, per
/// [RFC 7231 §5.3.5](https://tools.ietf.org/html/rfc7231#section-5.3.5).
public struct AcceptLanguageHeader: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let value: String

    // MARK: - Inits

    ///
    /// Initializes a new instance for an explicit, ordered list of ``LanguageTag``s.
    ///
    /// - Parameters:
    ///   - languageTag: The most preferred language.
    ///   - rest: Additional languages, in decreasing order of preference.
    ///
    public init(_ languageTag: LanguageTag, _ rest: LanguageTag...) {
        value = Self.weighted([languageTag] + rest)
    }

    #if canImport(Darwin)
    ///
    /// Initializes a new instance from the system's preferred languages
    /// (`Locale.preferredLanguages`), taking up to the top 6.
    ///
    /// - Important: Darwin only. `Locale.preferredLanguages` reads the user's Settings, which
    /// is not always what an app's outgoing requests should advertise.
    ///
    public init() {
        value = Self.weighted(Locale.preferredLanguages.prefix(6).map(LanguageTag.init))
    }
    #endif

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<AcceptLanguageHeader>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            HeaderNode(
                key: "Accept-Language",
                value: property.value,
                strategy: inputs.environment.headerStrategy,
                separator: inputs.environment.headerSeparator
            )
        )
    }

    // MARK: - Private static methods

    /// Joins `tags` into a single `Accept-Language` value, assigning each a descending `q`
    /// weight: `1.0`, `0.9`, `0.8`, ... floored at `0.1` so a longer list never reaches zero.
    private static func weighted(_ tags: [LanguageTag]) -> String {
        tags.enumerated()
            .map { index, tag in
                let quality = max(0.1, 1 - Double(index) * 0.1)
                return "\(tag.rawValue);q=\(quality.fixed(fractionDigits: 1))"
            }
            .joined(separator: ", ")
    }
}
