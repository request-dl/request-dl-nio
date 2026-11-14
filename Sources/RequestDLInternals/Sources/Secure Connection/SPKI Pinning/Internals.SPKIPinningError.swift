//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Thrown when an `SPKIPinning` declaration doesn't contribute a single pin.
    ///
    /// Every executor reads an empty pin set as "nothing to pin against" and falls back to plain
    /// chain validation, which is what makes a `.strict` policy with no pins fail *open*. An
    /// `SPKIPinning { ... }` whose content produced nothing (an empty `PropertyForEach`, a false
    /// `if`, or `SPKIHash`es declared somewhere only `SPKIPinning` can see) is therefore rejected
    /// rather than accepted as a policy that quietly pins nothing.
    package struct SPKIPinningError: Swift.Error, CustomStringConvertible, Sendable {
        package var description: String {
            "Invalid SPKI pinning: SPKIPinning declares no SPKIHash, so it would pin nothing and every certificate chain the system trusts would be accepted. Declare at least one SPKIHash inside it, or remove SPKIPinning."
        }

        package init() {}
    }
}
