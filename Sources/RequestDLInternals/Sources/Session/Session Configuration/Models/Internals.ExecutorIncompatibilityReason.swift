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
        /// A `certificateChain` resolving to more than one certificate (a leaf plus at least one
        /// intermediate).
        ///
        /// `Internals.SecureConnection.makeLocalIdentityForNetworkFramework()` only ever builds
        /// its `SecIdentity` from the chain's first certificate; AsyncHTTPClient's
        /// NIOTransportServices bridge has no API to carry supplementary certificates alongside
        /// it the way `.urlSession` (`URLCredential(identity:certificates:persistence:)`) or
        /// `.nio` (NIOSSL's own `TLSConfiguration.certificateChain`) do. A server that doesn't
        /// already have the intermediate in its own trust store can't complete the chain from a
        /// leaf-only presentation and rejects the handshake with `unknown_ca`.
        case multipleClientCertificatesUnderNetworkFramework
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
