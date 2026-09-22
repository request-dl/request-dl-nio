//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// One entry per configuration field that keeps a session off a given executor.
    ///
    /// Named per field, not per executor, since the same field can be fine on one executor and
    /// not another: the `*IncompatibilityReasons()` functions decide which of these apply for
    /// which executor.
    package enum ExecutorIncompatibilityReason: Sendable, Hashable {
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
        case dnsOverrideUnderURLSession
        case http1OnlyUnderURLSession
        case proxyConnectHeadersUnderURLSession
        /// No `URLCredential` shape can carry an arbitrary bearer token (only user/password or
        /// identity/certificates), so `.bearer` proxy authorization is unanswerable through the
        /// proxy authentication challenge delegate regardless of platform.
        case proxyBearerAuthorizationUnderURLSession
        /// The mirror image of the `UnderURLSession` cases above: a configured
        /// `Decompressor.requiresURLSession` algorithm (`BrotliURLSessionOnlyAlgorithm`, or a
        /// third-party one answering the same way) rules out `.nio`/`.nioTransportServices`
        /// instead of `.urlSession`. Neither goes through CFNetwork, and `NIOHTTPCompression`
        /// has no decoder for whatever such an algorithm stands in for.
        case decompressionRequiresURLSession
        /// No longer produced by anything, and retained only so the public
        /// `ExecutorRequirementError.Reason` case mapped from it stays source-compatible.
        ///
        /// `maximumTLSVersion` is reachable under URLSession after all, via
        /// `URLSessionConfiguration.tlsMaximumSupportedProtocolVersion`; see
        /// `Internals.SecureConnection.urlSessionIncompatibilityReasons()` for the evidence and
        /// for the wrong premise this case originally rested on.
        case maximumTLSVersionUnderURLSession
        /// `URLSession` negotiates ALPN automatically and Info.plist has no key to override the
        /// protocol list it offers, so this has no reachable equivalent under URLSession at all.
        case applicationProtocolsUnderURLSession
    }
}
