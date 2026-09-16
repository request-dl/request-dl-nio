//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOSSL
#endif

extension Internals {

    /// Portable mirror of `NIOSSLSecureBytes`: the currency `Internals.PrivateKey.password`
    /// stores so a password-protected private key stays configurable without NIO.
    ///
    /// `RawBytesIdentityBuilder.decryptedRSAPrivateKeyDER(fromEncryptedPEM:password:)` (the
    /// `.urlSession` mTLS path's own PKCS#1 RSA decryption, Darwin-only, already NIO-free) reads
    /// this directly; `PrivateKey.build()` converts it to a real `NIOSSLSecureBytes` for NIOSSL's
    /// own `TLSConfiguration`.
    ///
    /// - Important: Unlike `NIOSSLSecureBytes`, this does **not** zero its storage on `deinit`.
    /// That is a real, deliberate simplification, not an oversight: a rigorous, compiler
    /// optimization-proof wipe needs more than a plain `[UInt8]` can give in pure Swift, and the
    /// data this carries is a caller-supplied password/passphrase, not derived key material — the
    /// actual cryptographic keys built from it are still handled by `Crypto`/NIOSSL/BoringSSL,
    /// which already zero what they own internally. Revisit only if a concrete threat model
    /// requires it.
    package struct SecureBytes: Sendable, Equatable, ExpressibleByArrayLiteral {

        // MARK: - Private properties

        private let storage: [UInt8]

        // MARK: - Inits

        package init(_ bytes: some Sequence<UInt8>) {
            storage = Array(bytes)
        }

        package init(arrayLiteral elements: UInt8...) {
            storage = elements
        }

        #if canImport(NIOCore)
        package init(_ secureBytes: NIOSSLSecureBytes) {
            storage = Array(secureBytes)
        }
        #endif

        // MARK: - Internal methods

        #if canImport(NIOCore)
        package func build() -> NIOSSLSecureBytes {
            NIOSSLSecureBytes(storage)
        }
        #endif
    }
}

// MARK: - RandomAccessCollection

extension Internals.SecureBytes: RandomAccessCollection {

    package var startIndex: Int { storage.startIndex }
    package var endIndex: Int { storage.endIndex }

    package subscript(position: Int) -> UInt8 {
        storage[position]
    }
}
