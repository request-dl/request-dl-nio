//
// See LICENSE for this package's licensing information.
//

/// A custom error type representing base URL-related errors.
///
/// ```swift
/// throw BaseURLError(
///    context: .invalidHost,
///    baseURL: "http://example.com"
/// )
/// ```
public struct BaseURLError: Error {

    ///
    /// The possible contexts for the base URL error.
    ///
    public enum Context: Sendable {
        /// The host string provided is invalid, as it should not include the protocol.
        case invalidHost

        /// The host string has an unexpected format and the host could not be extracted.
        case unexpectedHost

        /// The host string carries a user name or a password (`user:password@host`). They would not
        /// be sent, and a URL ends up in logs, so credentials go in ``Authorization``.
        case userInfoNotAllowed
    }

    // MARK: - Public properties

    /// The context of the error.
    public let context: Context

    /// The base URL associated with the error, with the user name and the password, if it had
    /// any, replaced by `REDACTED`: an error ends up in logs.
    public let baseURL: String

    // MARK: - Initializer

    ///
    /// Initializes a `BaseURLError` instance.
    ///
    /// - Parameters:
    ///    - context: The context of the error.
    ///    - baseURL: The base URL associated with the error.
    ///
    public init(
        context: Context,
        baseURL: String
    ) {
        self.context = context
        self.baseURL = baseURL
    }
}
