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
    /// `certificates` are the intermediates the client presents along with the identity, in the
    /// shape Network.framework wants them (see
    /// `HTTPClient.Configuration.NetworkFrameworkClientIdentity`): the chain that follows the
    /// identity's own certificate, **without** that leaf, ordered from the one that issued it up
    /// towards the root. Empty when the chain is the leaf alone.
    ///
    /// `@unchecked Sendable` because `SecIdentity` and `SecCertificate` are immutable,
    /// reference-counted Core Foundation objects and both properties are `let`s.
    package final class IdentityHandle: @unchecked Sendable {
        package let identity: SecIdentity
        package let certificates: [SecCertificate]

        package init(identity: SecIdentity, certificates: [SecCertificate] = []) {
            self.identity = identity
            self.certificates = certificates
        }
    }
}

#endif
