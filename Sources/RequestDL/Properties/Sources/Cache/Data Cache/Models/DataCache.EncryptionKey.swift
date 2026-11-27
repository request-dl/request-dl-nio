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
    /// A key has to be at least 16 bytes long. A shorter one (an empty one included) cannot be told
    /// from public material, so a cache that has it refuses the disk tier altogether instead of
    /// encrypting with it: see the initializers below.
    ///
    /// A decrypt failure (the wrong key, a rotated key, or a corrupted or tampered file) is
    /// always a cache miss, never a crash: the entry is treated as absent and re-fetched.
    public struct EncryptionKey: Sendable, Equatable {

        // MARK: - Internal properties

        let symmetricKey: SymmetricKey

        /// The key the names of the entries on disk are made with (see ``DiskStorage``), derived
        /// from `symmetricKey` with a label of its own. The key that seals the entries is never
        /// used as a MAC key as well.
        let nameKey: SymmetricKey

        /// The shortest key, in bytes, that ``DataCache`` takes for a key. Anything shorter is not
        /// worth encrypting with: it is a few bits of guessable material, or none at all, and
        /// whatever is derived from it is as public as it is.
        static let minimumByteCount = 16

        // MARK: - Inits

        /// - Parameter data: Raw key bytes. 32 bytes is recommended, for AES-256-GCM.
        ///
        /// The key has to be **at least 16 bytes** long. AES takes keys of 16, 24 or 32 bytes, and
        /// those are used as they are. A longer key of any other length is run through HKDF-SHA256
        /// into a 32-byte key instead. That does not add entropy to bytes that had little, so a
        /// key that is not already random should go through HKDF in the app, as the guide on
        /// encrypting the cache describes.
        ///
        /// A key shorter than 16 bytes (an empty one included, which is what a read of a missing
        /// Keychain item tends to give) is not turned into one: stretched to a key, it would be
        /// as good as public, and the cache would look encrypted while anyone could read it. This
        /// initializer does not fail, so that it stays as it was, but the key it makes is not
        /// usable: a ``DataCache`` that has it writes nothing to the disk tier and finds nothing
        /// in it. The memory tier keeps working.
        public init<Bytes: DataProtocol & Sendable>(_ data: Bytes) {
            self.init(SymmetricKey(data: Data(data)))
        }

        /// For apps that already manage their key material as a `Crypto.SymmetricKey`. The same
        /// goes for its size as for the bytes above: at least 16 bytes (128 bits), or the key is
        /// not usable.
        public init(_ symmetricKey: SymmetricKey) {
            switch symmetricKey.bitCount {
            case 128, 192, 256:
                self.symmetricKey = symmetricKey
            case ..<(Self.minimumByteCount * 8):
                // Left as it is, a size AES refuses: every seal and open with it throws, which
                // is how an entry that cannot be written or read is told from one that can.
                self.symmetricKey = symmetricKey
            default:
                self.symmetricKey = HKDF<SHA256>.deriveKey(
                    inputKeyMaterial: symmetricKey,
                    info: Data("request-dl.cache.encryption-key.v1".utf8),
                    outputByteCount: 32
                )
            }

            if symmetricKey.bitCount < Self.minimumByteCount * 8 {
                // Names made from the weak bytes could be tried against a list of URLs, so they
                // are made from bytes that have nothing to do with them. Nothing is written
                // under such a name anyway.
                self.nameKey = SymmetricKey(size: .bits256)
            } else {
                self.nameKey = HKDF<SHA256>.deriveKey(
                    inputKeyMaterial: self.symmetricKey,
                    info: Data("request-dl.cache.entry-name.v1".utf8),
                    outputByteCount: 32
                )
            }
        }
    }
}
