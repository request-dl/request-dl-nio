//
// See LICENSE for this package's licensing information.
//

import Crypto

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

extension Internals {

    /// Addresses an AES-GCM encrypted file on disk, chunked per
    /// ``Internals/EncryptedFileStreamBuffer``.
    ///
    /// Wraps a plain ``Internals/FileBufferURL`` for every resource-management concern
    /// (existence, creation, truncation, temporary-file removal), which the ciphertext-vs-
    /// plaintext distinction below does not change. `writtenBytes` is the one exception: it must
    /// report the *plaintext* size, not the real file size, because every cursor
    /// (`Internals.Buffer`'s `writerIndex`/`readableBytes`/`estimatedBytes`) is built on top of
    /// it, and `Internals.CacheControl.isCachedDataValid` compares `readableBytes` against the
    /// origin's plaintext `Content-Length` to decide whether a cache entry is still valid. If
    /// this reported ciphertext-plus-framing size instead, that comparison would fail for every
    /// encrypted entry, permanently, and the cache would never serve a hit.
    ///
    /// - Important: This type is only ever meant to be constructed directly, with a key already
    /// in hand — see ``Internals/EncryptedFileStreamBuffer`` and `DiskStorage`'s
    /// `dataBuffer(for:)`. `make(from:)` deliberately does not implement the "discover an
    /// encrypted buffer from a bare `URL`" path: there is no channel through that static factory
    /// to supply a key, and a key must never be smuggled through a `Foundation.URL`.
    package struct EncryptedFileBufferURL: BufferURL {

        // MARK: - Internal static properties

        /// - Warning: Reachable only if something bypasses `Internals.Buffer<EncryptedFileStreamBuffer>
        /// (addressing:)` and calls the no-argument or `Foundation.URL`-based `Internals.Buffer`
        /// initializers against this stream type instead — there is no legitimate call path to
        /// this property. See ``Internals/EncryptedFileStreamBuffer`` for why a plaintext
        /// fallback here would be a footgun worth avoiding outright.
        package static var temporaryURL: Internals.EncryptedFileBufferURL {
            Internals.assertionFailure(
                "EncryptedFileBufferURL.temporaryURL reached — a caller bypassed "
                    + "Internals.Buffer<EncryptedFileStreamBuffer>(addressing:) with a key already in "
                    + "hand, and fell back to the keyless generic Buffer construction path instead."
            )

            // Release builds don't trap on the assertion above. A random, immediately discarded
            // key still produces a self-consistent (if permanently unreadable) encrypted temp
            // buffer — safe, since nothing can ever decrypt it, rather than the alternative of
            // silently reading/writing the target file as plaintext through a mismatched stream.
            return Internals.EncryptedFileBufferURL(
                inner: .temporaryURL,
                key: SymmetricKey(size: .bits256)
            )
        }

        // MARK: - Internal properties

        let inner: Internals.FileBufferURL
        let key: SymmetricKey

        /// The logical plaintext size, derived from the real on-disk (ciphertext) size. See the
        /// type-level note above for why this must not simply delegate to `inner.writtenBytes`.
        package var writtenBytes: Int {
            get async {
                Internals.EncryptedFileStreamBuffer.plaintextSize(fromRawSize: await inner.writtenBytes)
            }
        }

        // MARK: - Inits

        package init(inner: Internals.FileBufferURL, key: SymmetricKey) {
            self.inner = inner
            self.key = key
        }

        // MARK: - Internal static methods

        /// Always `nil`. See the type-level note: an encrypted buffer is never discoverable from
        /// a bare `URL` without a key, so this path is intentionally left unimplemented, matching
        /// the protocol's own default and `Internals.FileBufferURL`'s own gap for `ByteURL`.
        package static func make(from url: URL) -> Internals.EncryptedFileBufferURL? {
            nil
        }

        // MARK: - Internal methods

        package func isResourceAvailable() async -> Bool {
            await inner.isResourceAvailable()
        }

        package func createResourceIfNeeded() async {
            await inner.createResourceIfNeeded()
        }

        /// Wipes the header and base nonce along with everything else. The next write starts a
        /// fresh record, with a fresh nonce — exactly as if the file never existed.
        package func truncate() async {
            await inner.truncate()
        }

        package func removeIfTemporary() async {
            await inner.removeIfTemporary()
        }
    }
}
