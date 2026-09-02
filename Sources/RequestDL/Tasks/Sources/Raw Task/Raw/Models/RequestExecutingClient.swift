//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// What `RawTask`/`Internals.CacheControl` actually need from a client, independent of which
/// transport is underneath.
///
/// Declared here, in `RequestDL`, rather than under `Internals` in `RequestDLInternals`: both
/// methods take a `RequestConfiguration`, a `RequestDL`-only type, and `RequestDLInternals` can't
/// depend back on the module that depends on it. `Internals.Client` conforms in this same module
/// (see `Internals.Client+RequestExecutingClient.swift`) for exactly that reason -- Swift allows a
/// type from one module to conform to a protocol declared in another as long as one of the two is
/// local to the conforming extension's module, which is the case here.
///
/// Deliberately minimal: only what `RawTask.result()` and `Internals.CacheControl` actually call
/// today. Lifecycle concerns (`isRunning`/`shutdown()`) stay on the concrete client types --
/// `Internals.ClientManager` manages those directly, this protocol's callers never do.
package protocol RequestExecutingClient: Sendable {

    /// Runs `configuration`, returning a `SessionTask` whose response streams upload progress,
    /// the response head, and the body -- `cache`, when non-`nil`, is teed a copy of every
    /// downloaded chunk as it arrives, the same way the NIO backend's own cache write-through
    /// already works (see `Internals.DownloadBuffer.cacheStream(_:)`).
    func execute(
        configuration: RequestConfiguration,
        cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
        logger: Internals.TaskLogger?
    ) async throws -> SessionTask

    /// Runs `configuration` and returns just the response head -- what
    /// `Internals.CacheControl`'s conditional-revalidation request (`If-None-Match`/
    /// `If-Modified-Since`) needs to decide whether a cached entry is still fresh, without paying
    /// for a full `SessionTask`/streaming response it would otherwise throw away.
    func revalidationHead(
        configuration: RequestConfiguration,
        logger: Internals.TaskLogger?
    ) async throws -> Internals.ResponseHead
}
