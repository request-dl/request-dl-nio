//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Runs `body` to the end even when the calling Task is cancelled, for work that must not be
    /// skipped half way: closing a file handle.
    ///
    /// `NIOFileSystem` hands `close()` to its thread pool with `runIfActive`, which drops the
    /// work with a `CancellationError` when the calling Task is already cancelled. The descriptor
    /// then stays open, and releasing the handle after that is a `fatalError` ("Leaking file
    /// descriptor"), in release builds too. A request that is cancelled closes its files from a
    /// cancelled Task, so every `close()` on that path has to go through here.
    ///
    /// The detached Task starts outside the caller's cancellation, and awaiting its `value` does
    /// not pass the caller's cancellation on to it.
    ///
    /// - Important: Only for teardown. Anything that can take long and that a cancelled caller
    ///   would rather abandon does not belong here, because this waits for it.
    package static func uncancellable<Result: Sendable>(
        _ body: @escaping @Sendable () async throws -> Result
    ) async throws -> Result {
        try await _Concurrency.Task.detached {
            try await body()
        }
        .value
    }
}
