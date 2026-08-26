//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// One entry per configuration field that keeps a session off a given executor.
    ///
    /// Named per field, not per executor, since the same field can be fine on one executor and
    /// not another -- the `*IncompatibilityReasons()` functions decide which of these apply for
    /// which executor.
    package enum ExecutorIncompatibilityReason: Sendable, Hashable {
        case certificateChain
        case privateKey
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
        case noHostnameVerificationUnderNetworkFramework
        case additionalTrustRootsUnderNetworkFramework
        case dnsOverrideUnderURLSession
        case http1OnlyUnderURLSession
        case proxyConnectHeadersUnderURLSession
        /// No `URLCredential` shape can carry an arbitrary bearer token (only user/password or
        /// identity/certificates), so `.bearer` proxy authorization is unanswerable through the
        /// proxy authentication challenge delegate regardless of platform.
        case proxyBearerAuthorizationUnderURLSession
        case decompressionDisabledUnderURLSession
    }
}
