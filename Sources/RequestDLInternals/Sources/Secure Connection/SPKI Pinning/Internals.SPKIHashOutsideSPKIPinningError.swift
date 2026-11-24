//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Thrown when an `SPKIHash` is declared anywhere but inside an `SPKIPinning`.
    ///
    /// `SPKIPinning` only collects the `SPKIHash`es nested in its own content, so one declared
    /// elsewhere (`SecureConnection { SPKIHash(...) }`, or left behind by a refactor that moved it
    /// out) would pin nothing, and the connection would be validated by the certificate chain alone.
    /// That is the same fail-open ``SPKIPinningError`` closes for an empty `SPKIPinning`, so it is
    /// rejected instead of being dropped with a log that Release builds don't even emit.
    package struct SPKIHashOutsideSPKIPinningError: Swift.Error, CustomStringConvertible, Sendable {
        package var description: String {
            "Invalid SPKI pinning: an SPKIHash is declared outside SPKIPinning, so it would pin nothing and every certificate chain the system trusts would be accepted. Move the SPKIHash inside an SPKIPinning, or remove it."
        }

        package init() {}
    }
}
