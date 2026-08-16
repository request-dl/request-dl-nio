//
// See LICENSE for this package's licensing information.
//

import NIOCore

/// A completed session's cancellation seed together with its response.
///
/// Holds `Internals.AsyncResponse` rather than converting it into `RequestDL`'s
/// public `AsyncResponse` wrapper here -- that wrapper is a `RequestDL`-domain concept,
/// so building it from `seed`/`response` is left to `RequestDL`'s own call sites.
package struct SessionTask: Sendable {

    // MARK: - Internal properties

    package let seed: Internals.TaskSeed
    package let response: Internals.AsyncResponse

    // MARK: - Inits

    package init(
        seed: Internals.TaskSeed,
        response: Internals.AsyncResponse
    ) {
        self.seed = seed
        self.response = response
    }

    package init(_ response: Internals.AsyncResponse) {
        self.response = response
        self.seed = .withoutCancellation
    }
}
