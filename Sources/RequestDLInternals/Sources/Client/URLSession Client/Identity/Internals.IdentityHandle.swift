//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Security

extension Internals {

    /// One `SecIdentity` built in memory by
    /// `Internals.RawBytesIdentityBuilder.makeIdentity(certificateDER:privateKeyDER:)`.
    ///
    /// The identity is a pairing of a certificate and a private key held by this object alone:
    /// nothing is stored in a Keychain, so there is nothing to count references for and nothing
    /// to delete. Two handles built from the same certificate/key pair are independent, and
    /// dropping one never affects the other, in this process or in any other.
    ///
    /// `@unchecked Sendable` because `SecIdentity` is an immutable, reference-counted Core
    /// Foundation object and `identity` is a `let`.
    package final class IdentityHandle: @unchecked Sendable {
        package let identity: SecIdentity

        package init(identity: SecIdentity) {
            self.identity = identity
        }
    }
}

#endif
