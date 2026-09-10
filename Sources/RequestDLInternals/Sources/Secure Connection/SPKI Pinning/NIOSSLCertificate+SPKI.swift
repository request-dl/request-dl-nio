//
// See LICENSE for this package's licensing information.
//

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
