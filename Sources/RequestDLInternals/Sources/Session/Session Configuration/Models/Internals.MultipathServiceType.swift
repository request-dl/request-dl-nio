//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Mirrors `URLSessionConfiguration.MultipathServiceType`'s cases. AsyncHTTPClient only
    /// exposes a plain on/off `enableMultipath` flag on `HTTPClient.Configuration`, with no
    /// equivalent to the handover/interactive/aggregate distinction, so the collapse to `Bool`
    /// happens inline as `self != .none` at the one call site that needs it
    /// (`Internals.Session.Configuration.build()`) rather than through a `build()` method here:
    /// that mapping is lossy (4 cases to 1), not a 1:1 translation like the other `Internals`
    /// enums in this file's sibling models.
    ///
    /// `.urlSession` is the one executor that can express the distinction in full; see
    /// `Internals.Session.Configuration.buildURLSessionConfiguration()`'s own `urlSessionServiceType`
    /// mapping for the 1:1 translation, gated to exactly the platform the property exists on.
    package enum MultipathServiceType: Sendable, Hashable {
        case none
        case handover
        case interactive
        case aggregate
    }
}
