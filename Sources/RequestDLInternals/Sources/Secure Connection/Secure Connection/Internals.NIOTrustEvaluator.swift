//
// See LICENSE for this package's licensing information.
//

// The `.nio` counterpart to `Internals.ServerTrustPolicy` (which only ever answers `.urlSession`'s
// `SecTrust`-based challenge). AsyncHTTPClient no longer bundles SPKI pinning -- `tlsPinning`/
// `SPKIPinningConfiguration` were removed upstream in the fork's 1.38.0 release, replaced by two
// thin, policy-free hooks (`HTTPClient.Configuration.tlsCustomVerification` for the NIOSSL backend,
// `.tlsCustomVerificationNetworkFramework` for the Network.framework one) that let a caller fully
// own the accept/reject decision. This type is what plugs RequestDL's own trust-root + SPKI pinning
// logic into those hooks, so `.nio` keeps working exactly as before from a caller's perspective.

import NIOCore
import NIOSSL

#if canImport(Darwin)
import Security
#endif

extension Internals {

    /// Resolves an `Internals.SecureConnection`'s trust roots and SPKI pins into the callbacks
    /// `.nio` needs. Off Darwin, `resolve(from:)` returns `nil` whenever no SPKI pins are
    /// configured, so the caller can skip installing any custom verification at all -- NIOSSL's
    /// own native trust-root handling (plain BoringSSL against the OS CA bundle, already honoring
    /// `TLSConfiguration.additionalTrustRoots` on its own) stays completely untouched, at no added
    /// cost, for the common case of not pinning.
    ///
    /// On Darwin, `resolve(from:)` *also* triggers on `additionalTrustRoots` and/or
    /// `.noHostnameVerification` alone, with no pins: unlike NIOSSL, Network.framework has no
    /// native way to see `additionalTrustRoots` at all, and no simple flag to skip hostname
    /// matching the way NIOSSL's `certificateVerification` does (see `Internals.SecureConnection`'s
    /// own doc comment on `isCompatibleWithNetworkFramework`) -- both gaps only close through this
    /// evaluator's `tlsCustomVerificationNetworkFramework`. The actual accept/reject decision is
    /// `Internals.DarwinTrustEvaluation`'s, shared with `Internals.ServerTrustPolicy`
    /// (`.urlSession`) rather than reimplemented here: an empty pin set means "nothing to pin,"
    /// passing on chain validity alone rather than failing closed the way it would for a genuine,
    /// configured-but-unmatched pin; `skipsHostnameVerification` separately controls whether the
    /// chain check itself considers the hostname at all.
    package struct NIOTrustEvaluator: Sendable {

        /// Installs on `HTTPClient.Configuration.tlsCustomVerification` -- the NIOSSL backend,
        /// used everywhere except direct (non-proxied) connections on Apple platforms.
        package let tlsCustomVerification:
            @Sendable ([NIOSSLCertificate], EventLoopPromise<NIOSSLVerificationResult>) -> Void

        #if canImport(Darwin)
        /// Installs on `HTTPClient.Configuration.tlsCustomVerificationNetworkFramework` -- the
        /// Network.framework backend, used for direct connections on Apple platforms.
        package let tlsCustomVerificationNetworkFramework:
            @Sendable (SecTrust, @escaping @Sendable (Bool) -> Void) -> Void
        #endif

        package static func resolve(from secureConnection: Internals.SecureConnection) throws -> NIOTrustEvaluator? {
            let tlsPins = secureConnection.tlsPins ?? []
            let hasAdditionalTrustRoots = !(secureConnection.additionalTrustRoots ?? []).isEmpty

            #if canImport(Darwin)
            let skipsHostnameVerification = secureConnection.certificateVerification == .noHostnameVerification

            guard !tlsPins.isEmpty || hasAdditionalTrustRoots || skipsHostnameVerification else {
                return nil
            }
            #else
            guard !tlsPins.isEmpty else {
                return nil
            }
            #endif

            let isStrict = (secureConnection.tlsPinningPolicy ?? .strict) == .strict

            var trustRootCertificates: [NIOSSLCertificate] = []
            if let trustRoots = secureConnection.trustRoots {
                trustRootCertificates += try trustRoots.resolvedCertificates()
            }
            if let additionalTrustRoots = secureConnection.additionalTrustRoots {
                for additionalTrustRoot in additionalTrustRoots {
                    trustRootCertificates += try additionalTrustRoot.resolvedCertificates()
                }
            }

            #if canImport(Darwin)
            return try Self.makeDarwinEvaluator(
                pins: tlsPins,
                isStrict: isStrict,
                trustRootCertificates: trustRootCertificates,
                skipsHostnameVerification: skipsHostnameVerification
            )
            #else
            return try Self.makePortableEvaluator(
                pins: tlsPins,
                isStrict: isStrict,
                trustRootCertificates: trustRootCertificates
            )
            #endif
        }
    }
}
