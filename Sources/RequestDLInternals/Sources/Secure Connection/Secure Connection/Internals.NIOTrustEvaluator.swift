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
    /// `.nio` needs. `resolve(from:)` returns `nil` whenever no SPKI pins are configured, so the
    /// caller can skip installing any custom verification at all -- the TLS backend's own native
    /// trust-root handling (NIOSSL's BoringSSL/Security.framework-backed default on Darwin, plain
    /// BoringSSL against the OS CA bundle on Linux) stays completely untouched, at no added cost,
    /// for the common case of not pinning.
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
            guard let tlsPins = secureConnection.tlsPins, !tlsPins.isEmpty else {
                return nil
            }

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
                trustRootCertificates: trustRootCertificates
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
