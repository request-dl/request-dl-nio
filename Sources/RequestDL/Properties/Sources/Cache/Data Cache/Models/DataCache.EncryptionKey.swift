//
// See LICENSE for this package's licensing information.
//

import Crypto

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import protocol Foundation.DataProtocol
#endif

extension DataCache {

    /// A symmetric key ``DataCache`` uses to encrypt its disk tier at rest with AES-GCM.
    ///
    /// RequestDL does not manage key material: generating, rotating, and securely storing a key
    /// (Keychain, a KMS, whatever fits the app's own threat model) is the app's responsibility —
    /// this only carries key bytes across the boundary. Set it via ``DataCache/encryptionKey`` or
    /// the `.cache(...)` property's `encryptionKey` parameter. `nil` (the default) leaves the
    /// disk tier exactly as unencrypted as it has always been.
    ///
    /// A decrypt failure — the wrong key, a rotated key, or a corrupted/tampered file — is always
    /// a cache miss, never a crash: the entry is silently treated as absent and re-fetched.
    public struct EncryptionKey: Sendable, Equatable {

        // MARK: - Internal properties

        let symmetricKey: SymmetricKey

        // MARK: - Inits

        /// - Parameter data: Raw key bytes. 32 bytes is recommended, for AES-256-GCM.
        public init<Bytes: DataProtocol & Sendable>(_ data: Bytes) {
            symmetricKey = SymmetricKey(data: Data(data))
        }

        /// For apps that already manage their key material as a `Crypto.SymmetricKey`.
        public init(_ symmetricKey: SymmetricKey) {
            self.symmetricKey = symmetricKey
        }
    }
}
