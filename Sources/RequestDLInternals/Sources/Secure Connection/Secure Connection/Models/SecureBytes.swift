//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOSSL
#endif

/// A byte sequence for a password/passphrase — for instance, ``Internals/PrivateKey``'s
/// `password` — that stays constructible without NIO, while still storing straight into NIOSSL's
/// own `NIOSSLSecureBytes` (auto-zeroing storage included) whenever NIOSSL is actually available.
///
/// The single ``init(_:)`` behaves identically on every platform; only what it stores into
/// differs, gated by `#if canImport(NIOCore)`:
/// - `.nio`: a real `NIOSSLSecureBytes`, so this value gets NIOSSL's own zero-on-deallocation
///   guarantee for free, and ``build()`` returns it directly with no copy.
/// - `.bytes`: a plain `[UInt8]` fallback where NIOSSL isn't available. This does **not** zero
///   its storage on deallocation — a real, deliberate simplification for that path, not an
///   oversight: the data this carries is a caller-supplied password/passphrase, not derived key
///   material, and the actual cryptographic keys built from it are still handled by
///   `Crypto`/NIOSSL/BoringSSL, which already zero what they own internally.
public struct SecureBytes: Sendable, Equatable, ExpressibleByArrayLiteral {

    // MARK: - Private storage

    private enum Storage: Sendable, Equatable {
        case bytes([UInt8])
        #if canImport(NIOCore)
        case nio(NIOSSLSecureBytes)
        #endif
    }

    private let storage: Storage

    // MARK: - Inits

    /// Creates a secure byte sequence from any sequence of bytes, e.g. `"a password".utf8`.
    public init(_ bytes: some Sequence<UInt8>) {
        #if canImport(NIOCore)
        storage = .nio(NIOSSLSecureBytes(bytes))
        #else
        storage = .bytes(Array(bytes))
        #endif
    }

    public init(arrayLiteral elements: UInt8...) {
        self.init(elements)
    }

    #if canImport(NIOCore)
    /// Adopts an existing `NIOSSLSecureBytes` as is, with no copy.
    public init(_ secureBytes: NIOSSLSecureBytes) {
        storage = .nio(secureBytes)
    }
    #endif

    // MARK: - Internal methods

    #if canImport(NIOCore)
    package func build() -> NIOSSLSecureBytes {
        switch storage {
        case .nio(let secureBytes):
            return secureBytes
        case .bytes(let bytes):
            return NIOSSLSecureBytes(bytes)
        }
    }
    #endif
}

// MARK: - RandomAccessCollection

extension SecureBytes: RandomAccessCollection {

    public var startIndex: Int {
        switch storage {
        case .bytes(let bytes):
            return bytes.startIndex
        #if canImport(NIOCore)
        case .nio(let secureBytes):
            return secureBytes.startIndex
        #endif
        }
    }

    public var endIndex: Int {
        switch storage {
        case .bytes(let bytes):
            return bytes.endIndex
        #if canImport(NIOCore)
        case .nio(let secureBytes):
            return secureBytes.endIndex
        #endif
        }
    }

    public subscript(position: Int) -> UInt8 {
        switch storage {
        case .bytes(let bytes):
            return bytes[position]
        #if canImport(NIOCore)
        case .nio(let secureBytes):
            return secureBytes[position]
        #endif
        }
    }
}
