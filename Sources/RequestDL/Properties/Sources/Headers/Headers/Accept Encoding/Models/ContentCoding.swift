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
/// > Note: This package's built-in response decompression (`Internals.Decompression`, over
/// `AsyncHTTPClient`'s `NIOHTTPCompression`) only implements `gzip` and `deflate` — there is no
/// Brotli support in NIO yet. Advertising ``brotli`` here does not need it: it only tells the
/// server that a Brotli-encoded response is acceptable, and it is up to the caller to decode
/// it — for example by disabling automatic decompression and reading the raw
/// `Content-Encoding: br` body themselves.
public struct ContentCoding: Sendable, Hashable {

    // MARK: - Public static properties

    /// The `gzip` content coding.
    public static let gzip: ContentCoding = "gzip"

    /// The `deflate` content coding.
    public static let deflate: ContentCoding = "deflate"

    /// The `br` (Brotli) content coding.
    ///
    /// - Important: Neither `AsyncHTTPClient` nor `swift-nio-extras` decompresses Brotli, so
    /// this package never does it automatically. Only advertise it if the caller decodes the
    /// response body itself.
    public static let brotli: ContentCoding = "br"

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
