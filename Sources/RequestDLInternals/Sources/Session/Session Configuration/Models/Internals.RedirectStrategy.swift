//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Internals-layer counterpart to `RequestDL.RedirectStrategy`. Both transports (the NIO
    /// executor via an `AsyncHTTPClient.HTTPClientRedirectStrategy` adapter, and the `URLSession`
    /// executor directly from its redirect delegate) drive one of these, so a strategy configured
    /// through `RequestDL.RedirectStrategy` behaves identically under either.
    package protocol RedirectStrategy: Sendable {
        func redirectDecision(for context: Internals.RedirectContext) throws -> Internals.RedirectDecision
    }
}
