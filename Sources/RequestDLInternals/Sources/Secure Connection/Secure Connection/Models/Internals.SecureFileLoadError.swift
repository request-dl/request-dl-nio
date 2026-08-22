//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Carries the raw context of a certificate/private key file load failure up to `RequestDL`.
    ///
    /// `RequestDL`'s public `SecureFileError` -- the documented, user-facing error -- lives in the
    /// `RequestDL` module and cannot be referenced from here, since `RequestDL` depends on this
    /// module rather than the other way around. `Internals.Certificate`/`Internals.PrivateKey`
    /// throw this instead; `RequestDL` catches it where the client bootstraps and rewraps it into
    /// `SecureFileError`.
    package struct SecureFileLoadError: Error, Sendable {

        package enum Resource: Sendable, Hashable {
            case certificate
            case privateKey
        }

        package let resource: Resource
        package let path: String
        package let underlying: any Error

        package init(resource: Resource, path: String, underlying: any Error) {
            self.resource = resource
            self.path = path
            self.underlying = underlying
        }
    }
}
