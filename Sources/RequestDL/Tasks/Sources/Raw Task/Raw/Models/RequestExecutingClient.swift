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
/// (see `Internals.Client+RequestExecutingClient.swift`) for exactly that reason: Swift allows a
/// type from one module to conform to a protocol declared in another as long as one of the two is
/// local to the conforming extension's module, which is the case here.
///
/// Deliberately minimal: only what `RawTask.result()` and `Internals.CacheControl` actually call
/// today. Lifecycle concerns (`isRunning`/`shutdown()`) stay on the concrete client types;
/// `Internals.ClientManager` manages those directly, this protocol's callers never do.
package protocol RequestExecutingClient: Sendable {

    /// Runs `configuration`, returning a `SessionTask` whose response streams upload progress,
    /// the response head, and the body. `cache`, when non-`nil`, is teed a copy of every
    /// downloaded chunk as it arrives, the same way the NIO backend's own cache write-through
    /// already works (see `Internals.DownloadBuffer.cacheStream(_:)`).
    ///
    /// - Parameter decompression: Not read from `configuration`, since it lives on `Session`, not
    /// per-request, so it travels separately. Each conformance is responsible for whatever its
    /// own transport needs done with it: the `.urlSession` one derives `Accept-Encoding` from it
    /// and mutates the built request before sending, the `.nio` one only forwards it onward,
    /// since native gzip/deflate handling there is already configured once, at pooled-client
    /// creation time, via `Internals.Session.Configuration.build()`. Both thread it into
    /// `Internals.AsyncResponse` for the manual-dispatch decode this package's own code performs
    /// for whatever the native handling on that executor leaves untouched.
    func execute(
        configuration: RequestConfiguration,
        decompression: Internals.Decompression,
        cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
        logger: Internals.TaskLogger?
    ) async throws -> SessionTask

    /// Runs `configuration` and returns just the response head: what
    /// `Internals.CacheControl`'s conditional-revalidation request (`If-None-Match`/
    /// `If-Modified-Since`) needs to decide whether a cached entry is still fresh, without paying
    /// for a full `SessionTask`/streaming response it would otherwise throw away.
    func revalidationHead(
        configuration: RequestConfiguration,
        logger: Internals.TaskLogger?
    ) async throws -> Internals.ResponseHead
}
