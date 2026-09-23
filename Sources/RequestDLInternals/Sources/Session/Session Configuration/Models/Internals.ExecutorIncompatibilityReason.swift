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
        /// `URLSessionConfiguration` has no maximum-TLS-version API. Unlike `minimumTLSVersion`
        /// (reachable under URLSession via an ATS `NSExceptionMinimumTLSVersion` entry in
        /// Info.plist), there is no App Transport Security key for a maximum either, so this has
        /// no reachable equivalent under URLSession at all.
        case maximumTLSVersionUnderURLSession
        /// `URLSession` negotiates ALPN automatically and Info.plist has no key to override the
        /// protocol list it offers, so this has no reachable equivalent under URLSession at all.
        case applicationProtocolsUnderURLSession
        /// A client identity (`certificateChain`/`privateKey`) configured alongside a `proxy`.
        ///
        /// Network.framework's own TLS only ever reads the client identity from
        /// `tlsLocalIdentityNetworkFramework` (see `Internals.SecureConnection
        /// .makeTLSConfigurationByContext(isCompatibleWithNetworkFramework:)`'s own doc comment
        /// on why `certificateChain`/`privateKey` are deliberately left off the NIOSSL
        /// `TLSConfiguration` whenever Network.framework is in play), which is correct for a
        /// *direct* NIOTransportServices connection. It's wrong once a proxy is configured
        /// alongside it: AsyncHTTPClient performs TLS for a *proxied* HTTPS connection through
        /// NIOSSL even on a NIOTransportServices event loop
        /// (`HTTPConnectionPool+Factory.swift`'s `setupTLSInProxyConnectionIfNeeded`, which reads
        /// the same NIOSSL `TLSConfiguration` the identity was left off of), so no client
        /// certificate would ever reach the proxy tunnel's TLS handshake.
        case clientIdentityWithProxyUnderNetworkFramework
    }
}
