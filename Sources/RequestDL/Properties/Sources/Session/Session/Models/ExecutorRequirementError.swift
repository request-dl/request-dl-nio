//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// An error thrown when `Session.requiredExecutor(_:)` pins a session to an ``Session/Executor``
/// its configuration cannot actually run on.
///
/// `RequestDLInternals`'s raw `Internals.IncompatibleExecutorConfigurationError` -- the internal,
/// package-visible error -- gets caught where the session bootstraps and rewrapped into this
/// type, following the same split `SecureFileError` uses for `Internals.SecureFileLoadError`.
public struct ExecutorRequirementError: Error, Sendable {

    /// One configuration field that keeps a session off the required executor.
    public enum Reason: Sendable, Hashable {
        case keyLogger
        case cipherSuites
        case cipherSuiteValues
        case renegotiationSupport
        case signingSignatureAlgorithms
        case verifySignatureAlgorithms
        case sendCANameList
        case shutdownTimeout
        case pskHint
        case pskIdentityResolver
        /// No longer produced: disabled hostname verification is reachable under Network.framework
        /// now, via `Internals.NIOTrustEvaluator` swapping in a hostname-less trust policy. Kept,
        /// rather than removed, for source compatibility with any exhaustive `switch` over `Reason`
        /// written before this case stopped being thrown.
        case noHostnameVerificationUnderNetworkFramework
        /// No longer produced: `additionalTrustRoots` alone (no SPKI pinning) is reachable under
        /// Network.framework now, via `Internals.NIOTrustEvaluator`. Kept, rather than removed, for
        /// source compatibility with any exhaustive `switch` over `Reason` written before this
        /// case stopped being thrown.
        case additionalTrustRootsUnderNetworkFramework
        case dnsOverrideUnderURLSession
        case http1OnlyUnderURLSession
        case proxyConnectHeadersUnderURLSession
        case proxyBearerAuthorizationUnderURLSession
        case decompressionRequiresURLSession

        // MARK: - Inits

        init(_ reason: Internals.ExecutorIncompatibilityReason) {
            switch reason {
            case .keyLogger:
                self = .keyLogger
            case .cipherSuites:
                self = .cipherSuites
            case .cipherSuiteValues:
                self = .cipherSuiteValues
            case .renegotiationSupport:
                self = .renegotiationSupport
            case .signingSignatureAlgorithms:
                self = .signingSignatureAlgorithms
            case .verifySignatureAlgorithms:
                self = .verifySignatureAlgorithms
            case .sendCANameList:
                self = .sendCANameList
            case .shutdownTimeout:
                self = .shutdownTimeout
            case .pskHint:
                self = .pskHint
            case .pskIdentityResolver:
                self = .pskIdentityResolver
            case .dnsOverrideUnderURLSession:
                self = .dnsOverrideUnderURLSession
            case .http1OnlyUnderURLSession:
                self = .http1OnlyUnderURLSession
            case .proxyConnectHeadersUnderURLSession:
                self = .proxyConnectHeadersUnderURLSession
            case .proxyBearerAuthorizationUnderURLSession:
                self = .proxyBearerAuthorizationUnderURLSession
            case .decompressionRequiresURLSession:
                self = .decompressionRequiresURLSession
            }
        }
    }

    // MARK: - Public properties

    /// The executor `Session.requiredExecutor(_:)` was pinned to.
    public let requiredExecutor: Session.Executor

    /// Every configuration field that conflicts with ``requiredExecutor``.
    public let reasons: [Reason]

    // MARK: - Inits

    init(_ error: Internals.IncompatibleExecutorConfigurationError) {
        self.requiredExecutor = Session.Executor(error.requiredExecutor)
        self.reasons = error.reasons.map(Reason.init)
    }
}

// MARK: - CustomStringConvertible

extension ExecutorRequirementError: CustomStringConvertible {

    public var description: String {
        """
        RequestDL could not honor .requiredExecutor(.\(requiredExecutor)) because this session's \
        configuration uses: \(reasons.map(\.description).joined(separator: ", ")). Use \
        .preferredExecutor(_:) instead to let RequestDL fall back automatically, or remove the \
        conflicting configuration.
        """
    }
}

// MARK: - Reason.CustomStringConvertible

extension ExecutorRequirementError.Reason: CustomStringConvertible {

    public var description: String {
        switch self {
        case .keyLogger:
            return "a TLS key logger"
        case .cipherSuites:
            return "a custom OpenSSL cipher suite string"
        case .cipherSuiteValues:
            return "custom cipher suite values"
        case .renegotiationSupport:
            return "custom TLS renegotiation support"
        case .signingSignatureAlgorithms:
            return "custom signing signature algorithms"
        case .verifySignatureAlgorithms:
            return "custom verify signature algorithms"
        case .sendCANameList:
            return "sending the CA name list"
        case .shutdownTimeout:
            return "a custom TLS shutdown timeout"
        case .pskHint:
            return "a PSK hint"
        case .pskIdentityResolver:
            return "a PSK identity resolver"
        case .noHostnameVerificationUnderNetworkFramework:
            // Unreachable -- see this case's own doc comment. Kept only so `description` stays
            // exhaustive without a `default:` swallowing future genuinely-new cases by accident.
            return "disabled hostname verification (unsupported under Network.framework)"
        case .additionalTrustRootsUnderNetworkFramework:
            // Unreachable -- see this case's own doc comment. Kept only so `description` stays
            // exhaustive without a `default:` swallowing future genuinely-new cases by accident.
            return "additional trust roots without also configuring SPKI pinning (unsupported under Network.framework)"
        case .dnsOverrideUnderURLSession:
            return "a DNS override (unsupported under URLSession)"
        case .http1OnlyUnderURLSession:
            return "an HTTP/1-only version pin (unsupported under URLSession)"
        case .proxyConnectHeadersUnderURLSession:
            return "custom proxy CONNECT headers (unsupported under URLSession)"
        case .proxyBearerAuthorizationUnderURLSession:
            return "a bearer-token proxy authorization (unsupported under URLSession)"
        case .decompressionRequiresURLSession:
            return
                "a decompression algorithm that only works under URLSession (unsupported under NIO/NIOTransportServices)"
        }
    }
}
