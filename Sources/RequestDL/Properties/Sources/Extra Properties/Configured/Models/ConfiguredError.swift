//
// See LICENSE for this package's licensing information.
//

/// A custom error type representing invalid `Configured` configuration.
///
/// ```swift
/// throw ConfiguredError(context: .invalidAuthorizationConfiguration)
/// ```
public struct ConfiguredError: Error {

    ///
    /// The possible contexts for the configured error.
    ///
    public enum Context: Sendable {
        /// `authorization.scheme` (or `proxy.authorization.scheme`) was specified but is neither
        /// `"basic"` nor `"bearer"`, or the fields required by the specified scheme are missing
        /// (`username`/`password` or `credentials` for `"basic"`, `token` for `"bearer"`).
        case invalidAuthorizationConfiguration

        /// `proxy.enabled` is `true` but `proxy.host` is missing, `proxy.type` is neither
        /// `"http"` nor `"socks"`, `proxy.port` is missing for an `"http"` proxy, or
        /// `proxy.authorization`/`proxy.connectHeaders` is specified for a `"socks"` proxy.
        case invalidProxyConfiguration
    }

    // MARK: - Public properties

    /// The context of the error.
    public let context: Context

    // MARK: - Initializer

    ///
    /// Initializes a `ConfiguredError` instance.
    ///
    /// - Parameter context: The context of the error.
    ///
    public init(context: Context) {
        self.context = context
    }
}
