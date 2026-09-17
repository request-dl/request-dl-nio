//
// See LICENSE for this package's licensing information.
//

// `Internals.DarwinTrustEvaluation.chainSPKIDERBytes(of:)` prefers this, BoringSSL-backed path
// over its own `X509`/`SwiftASN1` one whenever NIOSSL is available: BoringSSL's ASN.1 parser is
// the one every TLS handshake in this package already trusts, and is far more battle-tested
// against oddly-but-validly-encoded real-world certificates than `swift-certificates`'s own. The
// `X509`-based path exists only for a build without NIOSSL, not as the default.
#if canImport(NIOCore)

import NIOSSL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension NIOSSLCertificate {

    /// The DER-encoded SubjectPublicKeyInfo structure of this certificate's public key: what an
    /// `Internals.SPKIHash` pin's digest is computed over. `nil` if the public key can't be
    /// extracted or exported, which isn't expected for a certificate NIOSSL has already parsed.
    package func spkiDERBytes() -> Data? {
        guard
            let publicKey = try? extractPublicKey(),
            let spkiBytes = try? publicKey.toSPKIBytes()
        else {
            return nil
        }

        return Data(spkiBytes)
    }
}

#endif
