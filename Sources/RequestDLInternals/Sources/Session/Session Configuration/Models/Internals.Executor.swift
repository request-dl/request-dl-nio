//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// The transport a `Session` ultimately executes a request through.
    ///
    /// Three independent capability checks decide which executor a given configuration can run
    /// on: `.urlSession` and `.nioTransportServices` are not a strict hierarchy of each other,
    /// since some fields are reachable on one and not the other. `.nio` is the universal
    /// fallback: every configuration is compatible with it.
    ///
    /// `.nioTransportServices`/`.nio` only exist where NIO does. `.urlSession` is the only
    /// executor left standing without it, which is also the only combination that makes sense:
    /// every other executor-agnostic file in this package already assumes non-Darwin means NIO
    /// (see `Internals.Session.Configuration.resolveExecutor()`), so a NIO-less build is a
    /// Darwin/`.urlSession`-only build by construction, not a fourth configuration to support.
    package enum Executor: Sendable, Hashable {
        case urlSession
        #if canImport(NIOCore)
        case nioTransportServices
        case nio
        #endif
    }
}
