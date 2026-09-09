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

        /// `cachePolicy` was specified but is neither `"memory"`, `"disk"`, nor `"all"`.
        case invalidCachePolicy

        /// `cacheStrategy` was specified but is none of the ``CacheStrategy`` case names.
        case invalidCacheStrategy

        /// `secureConnection.privateKey.format` was specified but is neither `"pem"` nor
        /// `"der"`, `secureConnection.tlsMinimumVersion`/`secureConnection.tlsMaximumVersion`
        /// was specified but is none of `"1.0"`, `"1.1"`, `"1.2"`, `"1.3"`,
        /// `secureConnection.spkiPinning.pins` was specified but empty, or
        /// `secureConnection.spkiPinning.policy` was specified but is neither `"strict"` nor
        /// `"audit"`.
        case invalidSecureConnectionConfiguration

        /// `redirect.mode` was specified but is neither `"follow"` nor `"disallow"`.
        case invalidRedirectConfiguration
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
