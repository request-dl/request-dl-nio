//
// See LICENSE for this package's licensing information.
//

/// A completed session's cancellation seed together with its response.
///
/// Holds `Internals.AsyncResponse` rather than converting it into `RequestDL`'s
/// public `AsyncResponse` wrapper here, since that wrapper is a `RequestDL`-domain concept,
/// so building it from `seed`/`response` is left to `RequestDL`'s own call sites.
package struct SessionTask: Sendable {

    // MARK: - Internal properties

    package let seed: Internals.TaskSeed
    package let response: Internals.AsyncResponse

    /// Where the transport reports what each exchange on the wire measured.
    ///
    /// `nil` when nothing went over the wire, as with a response served from the cache.
    package let metrics: Internals.RequestMetricsCollector?

    // MARK: - Inits

    package init(
        seed: Internals.TaskSeed,
        response: Internals.AsyncResponse,
        metrics: Internals.RequestMetricsCollector? = nil
    ) {
        self.seed = seed
        self.response = response
        self.metrics = metrics
    }

    package init(_ response: Internals.AsyncResponse) {
        self.response = response
        self.seed = .withoutCancellation
        self.metrics = nil
    }
}
