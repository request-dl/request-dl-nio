//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// Sets the `Accept-Encoding` header in the request.
///
/// Each coding is assigned a descending `q` weight by position, per
/// [RFC 7231 §5.3.1](https://tools.ietf.org/html/rfc7231#section-5.3.1):
///
/// ```swift
/// AcceptEncodingHeader(.gzip, .deflate)
/// // "gzip;q=1.0, deflate;q=0.9"
/// ```
///
/// > Important: There is no default value. Only advertise a coding something in the pipeline
/// can actually decompress — either this package's own response decompression (see
/// ``RequestDL/Session``, off by default and limited to `gzip`/`deflate`), or, for ``ContentCoding/brotli``,
/// a decoder the caller runs itself against the raw response body.
public struct AcceptEncodingHeader: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let value: String

    // MARK: - Inits

    ///
    /// Initializes a new instance for an explicit, ordered list of ``ContentCoding``s.
    ///
    /// - Parameters:
    ///   - coding: The most preferred content coding.
    ///   - rest: Additional codings, in decreasing order of preference.
    ///
    public init(_ coding: ContentCoding, _ rest: ContentCoding...) {
        value = Self.weighted([coding] + rest)
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<AcceptEncodingHeader>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            HeaderNode(
                key: "Accept-Encoding",
                value: property.value,
                strategy: inputs.environment.headerStrategy,
                separator: inputs.environment.headerSeparator
            )
        )
    }

    // MARK: - Private static methods

    /// Joins `codings` into a single `Accept-Encoding` value, assigning each a descending `q`
    /// weight: `1.0`, `0.9`, `0.8`, ... floored at `0.1` so a longer list never reaches zero.
    private static func weighted(_ codings: [ContentCoding]) -> String {
        codings.enumerated()
            .map { index, coding in
                let quality = max(0.1, 1 - Double(index) * 0.1)
                return "\(coding.rawValue);q=\(quality.fixed(fractionDigits: 1))"
            }
            .joined(separator: ", ")
    }
}
