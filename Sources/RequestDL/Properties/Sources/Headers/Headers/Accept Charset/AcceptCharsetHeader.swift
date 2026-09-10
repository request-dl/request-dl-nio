//
// See LICENSE for this package's licensing information.
//

/// Sets the `Accept-Charset` header in the request.
///
/// This is a specific feature that should be explored according to the needs of each endpoint. JSON in Swift, for
/// example, uses `UTF-8`, `UTF-16`, and `UTF-32` during decoding and fails if other charsets are used.
/// Therefore, always use this option only if it is truly necessary.
///
/// - Warning: `Accept-Charset` is a legacy header the web platform has moved away from. The
/// WHATWG Fetch Standard lists it among the forbidden request-header names a browser refuses to
/// let a caller set at all (`fetch()`/`XMLHttpRequest.setRequestHeader` both reject it).
///
/// Browsers stopped sending it on ordinary navigations years ago. Most servers, and every JSON
/// endpoint (UTF-8 by definition), already ignore it. Sending it today mostly just signals a
/// non-browser client.
///
/// Prefer negotiating charset through the response's own `Content-Type`, or
/// an application-level convention with the server, instead.
@available(
    *,
    deprecated,
    message:
        "Accept-Charset is a legacy header most servers already ignore, and the WHATWG Fetch Standard forbids browsers from sending it at all. Negotiate charset through the response's own Content-Type instead."
)
public struct AcceptCharsetHeader: Property {

    // MARK: - Public properties

    /// Returns an exception since `Never` is a type that can never be constructed.
    public var body: Never {
        bodyException()
    }

    // MARK: - Private properties

    private let charset: Charset

    // MARK: - Inits

    ///
    /// Initializes a new instance for the given `Charset`.
    ///
    /// - Parameter charset: The charset to be accepted. Defaults is UTF-8.
    ///
    public init(_ charset: Charset) {
        self.charset = charset
    }

    // MARK: - Public static methods

    /// This method is used internally and should not be called directly.
    public static func _makeProperty(
        property: _GraphValue<AcceptCharsetHeader>,
        inputs: _PropertyInputs
    ) async throws -> _PropertyOutputs {
        property.assertPathway()
        return .leaf(
            HeaderNode(
                key: "Accept-Charset",
                value: property.charset.rawValue,
                strategy: inputs.environment.headerStrategy,
                separator: inputs.environment.headerSeparator
            )
        )
    }
}
