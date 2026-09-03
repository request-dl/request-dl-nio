//
// See LICENSE for this package's licensing information.
//

/// A content coding, as registered with IANA and used by the `Accept-Encoding` header.
///
/// ```swift
/// let coding: ContentCoding = .gzip
/// ```
///
/// > Important: If the desired coding is not included in the predefined static properties, use
/// a string literal to initialize an instance of `ContentCoding`.
///
/// > Note: There is no `.brotli` static property. This package's response decompression
/// (`Internals.Decompression`, over `AsyncHTTPClient`'s `NIOHTTPCompression`) only implements
/// `gzip` and `deflate` — there is no Brotli support yet. Advertising it here would let a
/// compliant server pick it and leave the response undecodable. `ContentCoding("br")` still
/// works from a string literal, for a caller with its own way of decoding the response.
public struct ContentCoding: Sendable, Hashable {

    // MARK: - Public static properties

    /// The `gzip` content coding.
    public static let gzip: ContentCoding = "gzip"

    /// The `deflate` content coding.
    public static let deflate: ContentCoding = "deflate"

    /// The `identity` content coding, i.e. no compression.
    public static let identity: ContentCoding = "identity"

    /// The `*` wildcard, matching any content coding not listed elsewhere in the header.
    public static let all: ContentCoding = "*"

    // MARK: - Internal properties

    let rawValue: String

    // MARK: - Inits

    ///
    /// Initializes a `ContentCoding` instance with a given string value.
    ///
    /// - Parameter rawValue: The content coding token, e.g. `"gzip"`.
    ///
    public init<S: StringProtocol>(_ rawValue: S) {
        self.rawValue = String(rawValue)
    }
}

// MARK: - ExpressibleByStringLiteral

extension ContentCoding: ExpressibleByStringLiteral {

    ///
    /// Initializes a `ContentCoding` instance using a string literal.
    ///
    /// - Parameter value: A string literal representing the content coding.
    ///
    public init(stringLiteral value: StringLiteralType) {
        self.rawValue = value
    }
}

// MARK: - LosslessStringConvertible

extension ContentCoding: LosslessStringConvertible {

    public var description: String {
        rawValue
    }
}
