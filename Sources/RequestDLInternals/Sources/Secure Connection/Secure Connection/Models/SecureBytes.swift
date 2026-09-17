//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import NIOSSL
#endif

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// A byte sequence for a password/passphrase, such as ``Internals/PrivateKey``'s `password`,
/// that stays constructible without NIO. When NIOSSL is available, it stores straight into
/// NIOSSL's own `NIOSSLSecureBytes` (auto-zeroing storage included).
///
/// The single ``init(_:)`` behaves identically on every platform; only what it stores into
/// differs, gated by `#if canImport(NIOCore)`:
/// - `.nio`: a real `NIOSSLSecureBytes`, so this value gets NIOSSL's own zero-on-deallocation
///   guarantee for free, and ``build()`` returns it directly with no copy.
/// - `.bytes`: a `ZeroingBytes` fallback where NIOSSL isn't available, backed by a heap
///   allocation that zeroes itself on deallocation the same way `NIOSSLSecureBytes` does, just
///   without NIOSSL/BoringSSL's `OPENSSL_cleanse` to lean on. See `ZeroingBytes`'s own doc
///   comment for the platform-specific primitive each case uses.
public struct SecureBytes: Sendable, Equatable, ExpressibleByArrayLiteral {

    // MARK: - Private storage

    private enum Storage: Sendable, Equatable {
        case bytes(ZeroingBytes)
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
        storage = .bytes(ZeroingBytes(bytes))
        #endif
    }

    public init(arrayLiteral elements: UInt8...) {
        self.init(elements)
    }

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

// MARK: - ZeroingBytes

/// Heap-allocated byte storage that overwrites itself with zeroes when deallocated, backing
/// `SecureBytes`'s NIOSSL-free fallback. Mirrors `NIOSSLSecureBytes`'s own `deinit`, but reaches
/// for each platform's own libc primitive instead of NIOSSL/BoringSSL's `OPENSSL_cleanse`
/// (unavailable here, since this path exists specifically for builds without NIOSSL):
/// - Darwin: `memset_s`, part of libc since macOS 10.9 / iOS 7 (C11 Annex K), needing no extra
///   dependency.
/// - Glibc/Musl: `explicit_bzero`, glibc's own answer to the same problem (available since
///   glibc 2.25), present in musl too.
///
/// Both are, like `memset_s`, defined specifically to survive dead-store elimination: unlike a
/// plain `memset`/manual loop right before a `free`, the optimizer cannot assume the compiler
/// knows their contract and drop the call as dead code.
package final class ZeroingBytes: @unchecked Sendable {

    // MARK: - Private properties

    private let buffer: UnsafeMutableBufferPointer<UInt8>

    // MARK: - Inits

    package init(_ bytes: some Sequence<UInt8>) {
        let bytes = Array(bytes)
        let buffer = UnsafeMutableBufferPointer<UInt8>.allocate(capacity: bytes.count)
        _ = buffer.initialize(fromContentsOf: bytes)
        self.buffer = buffer
    }

    deinit {
        guard let baseAddress = buffer.baseAddress else {
            return
        }

        #if canImport(Darwin)
        memset_s(baseAddress, buffer.count, 0, buffer.count)
        #elseif canImport(Glibc) || canImport(Musl)
        explicit_bzero(baseAddress, buffer.count)
        #else
        baseAddress.update(repeating: 0, count: buffer.count)
        #endif

        buffer.deallocate()
    }

    // MARK: - Internal properties

    package var startIndex: Int { buffer.startIndex }
    package var endIndex: Int { buffer.endIndex }

    // MARK: - Internal subscript

    package subscript(position: Int) -> UInt8 {
        buffer[position]
    }
}

extension ZeroingBytes: RandomAccessCollection {}

extension ZeroingBytes: Equatable {

    /// `_reusableItem(id:sessionConfiguration:)` runs this on every client-pool lookup for a
    /// `PrivateKey` with a password, so it needs to be an actual byte compare, not the default
    /// `RandomAccessCollection` witness `elementsEqual(_:)` would fall back to: that dispatches
    /// through `buffer`'s subscript one element at a time, with none of the single-call `memcmp`
    /// a contiguous, fixed-width buffer like this one can use instead.
    package static func == (_ lhs: ZeroingBytes, _ rhs: ZeroingBytes) -> Bool {
        guard lhs.buffer.count == rhs.buffer.count else {
            return false
        }

        guard let lhsBase = lhs.buffer.baseAddress, let rhsBase = rhs.buffer.baseAddress else {
            // Both empty: `baseAddress` is `nil` exactly when `count == 0`, already checked equal
            // above.
            return true
        }

        #if canImport(Darwin) || canImport(Glibc) || canImport(Musl)
        return memcmp(lhsBase, rhsBase, lhs.buffer.count) == .zero
        #else
        return lhs.buffer.elementsEqual(rhs.buffer)
        #endif
    }
}
