//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// A `SessionTask` was released or cancelled before its response was fully consumed.
    ///
    /// Transport-neutral on purpose -- fires from `Internals.CacheControl`'s cache-hit path
    /// (`makeCachedSession`) when the caller walks away
    /// before reading a cached response, which has nothing to do with which executor a cache
    /// *miss* would have run a real request on. Previously named `HTTPClientError.cancelled`
    /// there, an AsyncHTTPClient-specific type with no reason to appear on a path that never
    /// touches the network at all.
    package struct TaskCancelledError: Error, Sendable {
        package init() {}
    }
}
