//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// A byte sequence for a password/passphrase — for instance, ``PrivateKey``'s password
/// parameter — that doesn't require NIO the way `NIOSSLSecureBytes` does.
///
/// - Important: Unlike `NIOSSLSecureBytes`, this does not zero its storage on deallocation. See
/// ``Internals/SecureBytes``'s own doc comment (the internal type this wraps) for why that's a
/// deliberate simplification rather than an oversight.
public struct SecureBytes: Sendable, Equatable, ExpressibleByArrayLiteral {

    // MARK: - Internal properties

    let internalValue: Internals.SecureBytes

    // MARK: - Inits

    /// Creates a secure byte sequence from any sequence of bytes, e.g. `"a password".utf8`.
    public init(_ bytes: some Sequence<UInt8>) {
        internalValue = Internals.SecureBytes(bytes)
    }

    public init(arrayLiteral elements: UInt8...) {
        internalValue = Internals.SecureBytes(elements)
    }
}
