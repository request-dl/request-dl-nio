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
    /// (Keychain, a KMS, whatever fits the app's threat model) is the app's responsibility. This
    /// only carries key bytes across the boundary. Set it via ``DataCache/encryptionKey`` or
    /// the `.cache(...)` property's `encryptionKey` parameter. `nil` (the default) leaves the
    /// disk tier unencrypted.
    ///
    /// A decrypt failure (the wrong key, a rotated key, or a corrupted or tampered file) is
    /// always a cache miss, never a crash: the entry is treated as absent and re-fetched.
    public struct EncryptionKey: Sendable, Equatable {

        // MARK: - Internal properties

        let symmetricKey: SymmetricKey

        // MARK: - Inits

        /// - Parameter data: Raw key bytes. 32 bytes is recommended, for AES-256-GCM.
        ///
        /// AES takes keys of 16, 24 or 32 bytes, and those are used as they are. Any other length
        /// is not a key AES can use, and used to leave the cache silently unable to write or read
        /// anything: it is run through HKDF-SHA256 into a 32-byte key instead. That does not add
        /// entropy to bytes that had little, so a key that is not already random should go through
        /// HKDF in the app, as the guide on encrypting the cache describes.
        public init<Bytes: DataProtocol & Sendable>(_ data: Bytes) {
            self.init(SymmetricKey(data: Data(data)))
        }

        /// For apps that already manage their key material as a `Crypto.SymmetricKey`. The same
        /// goes for its size as for the bytes above.
        public init(_ symmetricKey: SymmetricKey) {
            switch symmetricKey.bitCount {
            case 128, 192, 256:
                self.symmetricKey = symmetricKey
            default:
                self.symmetricKey = HKDF<SHA256>.deriveKey(
                    inputKeyMaterial: symmetricKey,
                    info: Data("request-dl.cache.encryption-key.v1".utf8),
                    outputByteCount: 32
                )
            }
        }
    }
}
