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
        /// SPKI pinning is wired only through `SPKIPinningConfiguration`/`AsyncHTTPClient.SPKIHash`,
        /// which neither Network.framework's `getNWProtocolTLSOptions` bridge nor
        /// `Internals.URLSessionClient`'s `SecTrust`-based trust evaluation ever consults.
        case tlsPinning
        case dnsOverrideUnderURLSession
        case http1OnlyUnderURLSession
        case proxyConnectHeadersUnderURLSession
        /// No `URLCredential` shape can carry an arbitrary bearer token (only user/password or
        /// identity/certificates), so `.bearer` proxy authorization is unanswerable through the
        /// proxy authentication challenge delegate regardless of platform.
        case proxyBearerAuthorizationUnderURLSession
        case decompressionDisabledUnderURLSession
        /// `URLSessionConfiguration` has no maximum-TLS-version API, and unlike
        /// `minimumTLSVersion` (achievable under URLSession via an ATS `NSExceptionMinimumTLSVersion`
        /// entry in Info.plist), there is no App Transport Security key for a maximum either --
        /// so this has no reachable equivalent under URLSession at all.
        case maximumTLSVersionUnderURLSession
        /// `URLSession` negotiates ALPN automatically and Info.plist has no key to override the
        /// protocol list it offers, so this has no reachable equivalent under URLSession at all.
        case applicationProtocolsUnderURLSession
    }
}
