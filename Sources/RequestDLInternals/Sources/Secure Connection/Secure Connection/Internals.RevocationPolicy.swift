//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// How strictly a Darwin executor checks a peer certificate's revocation status (OCSP/CRL),
    /// layered on top of `SecTrust`'s own default check, which already runs automatically on
    /// every evaluation, but only on a best-effort basis: a revocation responder that can't be
    /// reached doesn't fail the handshake. NIOSSL/BoringSSL implements no revocation checking of
    /// its own, so this has no effect at all off Darwin.
    ///
    /// `Internals.NIOTrustEvaluator.resolve(from:)` only installs the custom verification this
    /// rides on when `canImport(Darwin)`, and `Internals.DarwinTrustEvaluation` is what both
    /// `.urlSession` (`ServerTrustPolicy`) and `.nio`/`.nioTransportServices` (`NIOTrustEvaluator`)
    /// share it through.
    package enum RevocationPolicy: Sendable, Hashable {

        /// Requires a definitive, verified positive response from OCSP or CRL before trusting the
        /// certificate, failing the handshake outright if that can't be obtained, including when
        /// the revocation responder is simply unreachable.
        case strict

        /// Skips network-based revocation checking (OCSP/CRL fetches) entirely, consulting only
        /// locally cached responses if any, and never fails a handshake over revocation status.
        ///
        /// - Warning: `SecPolicyCreateRevocation`'s `kSecRevocationNetworkAccessDisabled` flag,
        /// which this rides on, also disallows network access for intermediate CA issuer (AIA)
        /// fetching, not only revocation checking itself. A chain that depends on that to
        /// complete may fail to validate at all under this policy, independent of revocation
        /// status.
        case disabled
    }
}
