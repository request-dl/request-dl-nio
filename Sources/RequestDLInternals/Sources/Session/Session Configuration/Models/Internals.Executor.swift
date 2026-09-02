//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// The transport a `Session` ultimately executes a request through.
    ///
    /// Three independent capability checks decide which executor a given configuration can run
    /// on -- `.urlSession` and `.nioTransportServices` are not a strict hierarchy of each other,
    /// since some fields are reachable on one and not the other. `.nio` is the universal
    /// fallback: every configuration is compatible with it.
    package enum Executor: Sendable, Hashable {
        case urlSession
        case nioTransportServices
        case nio
    }
}
