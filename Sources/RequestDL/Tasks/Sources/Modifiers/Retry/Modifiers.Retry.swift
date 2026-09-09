//
// See LICENSE for this package's licensing information.
//

extension Modifiers {

    ///
    /// A `RequestTaskModifier` that retries the wrapped `RequestTask` according to a
    /// ``RetryPolicy`` while it keeps throwing.
    ///
    /// Each retry calls the original task's `result()` again, which re-resolves and re-sends the
    /// whole request from scratch -- see ``RetryPolicy`` for when that is, and isn't, safe to do.
    /// A `CancellationError` is never retried, regardless of `policy`.
    ///
    public struct Retry<Input: Sendable>: RequestTaskModifier {

        // MARK: - Internal properties

        let policy: RetryPolicy

        // MARK: - Public methods

        ///
        /// Executes `task`, retrying it according to `policy` while it keeps throwing.
        ///
        /// - Parameter task: The original `RequestTask`.
        /// - Throws: The last error thrown by `task`, once retries are exhausted or `policy`
        /// declines to retry it.
        /// - Returns: The result of the first successful attempt.
        ///
        public func body(_ task: Content) async throws -> Input {
            var attempt = 1

            while true {
                do {
                    return try await task.result()
                } catch {
                    guard
                        !(error is CancellationError),
                        attempt < policy.maxAttempts,
                        policy.shouldRetry(error)
                    else {
                        throw error
                    }

                    let delay = policy.delay(attempt)

                    if delay > .zero {
                        try await Task.sleep(nanoseconds: UInt64(delay.nanoseconds))
                    }

                    attempt += 1
                }
            }
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    ///
    /// Retries the task according to `policy` when it throws.
    ///
    /// Use this to smooth over transient failures -- a dropped connection, a momentary `5xx`
    /// surfaced by a modifier like ``RequestTask/acceptOnlyStatusCode(_:)`` further down the
    /// chain -- without hand-rolling a retry loop around `result()`. Because each retry re-runs
    /// the request from scratch, only apply it where that is safe: see ``RetryPolicy`` for the
    /// idempotency caveat before using it on requests with side effects.
    ///
    /// ```swift
    /// try await DataTask {
    ///     BaseURL("example.com")
    /// }
    /// .retry(.exponentialBackoff(3))
    /// .result()
    /// ```
    ///
    /// - Parameter policy: The ``RetryPolicy`` describing how many times to retry, the delay
    /// between attempts, and which errors are worth retrying.
    ///
    /// - Returns: A `ModifiedRequestTask` that retries the original task per `policy`.
    ///
    public func retry(
        _ policy: RetryPolicy
    ) -> ModifiedRequestTask<Modifiers.Retry<Element>> {
        modifier(Modifiers.Retry(policy: policy))
    }
}
