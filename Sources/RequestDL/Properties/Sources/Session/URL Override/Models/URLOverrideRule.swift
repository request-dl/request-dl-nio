//
// See LICENSE for this package's licensing information.
//

/// A single parsed origin/destination pair accumulated by ``URLOverride``.
struct URLOverrideRule: Sendable {

    let origin: URLOverrideEndpoint
    let destination: URLOverrideEndpoint
}
