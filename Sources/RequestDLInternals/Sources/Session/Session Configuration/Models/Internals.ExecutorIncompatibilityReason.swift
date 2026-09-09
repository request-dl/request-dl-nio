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
        /// Only a problem when SPKI pinning (`.tlsPinning`) *isn't* also active -- when it is,
        /// `Internals.NIOTrustEvaluator` reads `additionalTrustRoots` itself as part of building
        /// its own custom verification, on both the NIOSSL and Network.framework backends.
        case additionalTrustRootsUnderNetworkFramework
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
        /// instead of `.urlSession` -- neither goes through CFNetwork, and `NIOHTTPCompression`
        /// has no decoder for whatever such an algorithm stands in for.
        case decompressionRequiresURLSession
    }
}
