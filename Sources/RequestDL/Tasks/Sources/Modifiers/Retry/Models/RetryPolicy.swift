//
// See LICENSE for this package's licensing information.
//

/// A policy describing how a failed ``RequestTask`` should be retried by
/// ``RequestTask/retry(_:)``.
///
/// Retrying re-executes the whole request from scratch: the ``Property`` content behind the task
/// is resolved and sent again as if it were a brand-new call, not a resumption of the failed one.
/// That is safe for requests that are safe to repeat -- `GET`/`HEAD`, or any request whose body is
/// described declaratively (``Payload``'s `data`/`url`/`json` initializers, for instance) rather
/// than consumed from a caller-owned, single-use stream that can't be read a second time.
///
/// It is **not** safe by default for requests with side effects that aren't idempotent (a `POST`
/// that creates a resource, for example): if the original request actually reached the server but
/// its response was lost -- a timeout, a dropped connection -- retrying it can duplicate that side
/// effect. `RetryPolicy` has no visibility into the request it is applied to, so it cannot enforce
/// this on its own; scope `shouldRetry` and where `.retry(_:)` is applied in the call graph
/// accordingly.
///
/// ```swift
/// try await DataTask {
///     BaseURL("example.com")
/// }
/// .retry(.exponentialBackoff(3))
/// .result()
/// ```
public struct RetryPolicy: Sendable {

    // MARK: - Internal properties

    let maxAttempts: Int
    let shouldRetry: @Sendable (Error) -> Bool
    let delay: @Sendable (_ attempt: Int) -> UnitTime

    // MARK: - Inits

    ///
    /// Creates a policy with full control over the delay between attempts.
    ///
    /// - Parameters:
    ///   - maxAttempts: The maximum number of times the request is executed in total, including
    ///     the first attempt. Values below `1` are treated as `1`, i.e. no retry.
    ///   - shouldRetry: Called with each thrown error to decide whether it is worth retrying.
    ///     Returning `false` stops retrying and rethrows that error immediately. Defaults to
    ///     retrying every error except cancellation, which is never retried.
    ///   - delay: Called with the retry attempt number -- `1` for the delay before the second
    ///     overall attempt, `2` before the third, and so on -- to compute how long to wait
    ///     before it.
    ///
    public init(
        maxAttempts: Int,
        shouldRetry: @escaping @Sendable (Error) -> Bool = { _ in true },
        delay: @escaping @Sendable (_ attempt: Int) -> UnitTime
    ) {
        self.maxAttempts = max(1, maxAttempts)
        self.shouldRetry = shouldRetry
        self.delay = delay
    }

    // MARK: - Public static methods

    ///
    /// A policy that waits the same fixed interval before every retry.
    ///
    /// - Parameters:
    ///   - maxAttempts: The maximum number of times the request is executed in total.
    ///   - delay: The fixed interval to wait before every retry. Default is `.seconds(1)`.
    ///   - shouldRetry: Called with each thrown error to decide whether it is worth retrying.
    ///
    /// - Returns: A `RetryPolicy` with a fixed delay between attempts.
    ///
    public static func fixed(
        _ maxAttempts: Int,
        delay: UnitTime = .seconds(1),
        shouldRetry: @escaping @Sendable (Error) -> Bool = { _ in true }
    ) -> RetryPolicy {
        .init(maxAttempts: maxAttempts, shouldRetry: shouldRetry) { _ in delay }
    }

    ///
    /// A policy that grows the wait between attempts geometrically, up to a ceiling.
    ///
    /// - Parameters:
    ///   - maxAttempts: The maximum number of times the request is executed in total.
    ///   - baseDelay: How long to wait before the first retry. Default is `.seconds(1)`.
    ///   - multiplier: How much the delay grows after each attempt. Default is `2`.
    ///   - maxDelay: The longest delay allowed between attempts, regardless of how many have
    ///     already happened. Default is `.seconds(30)`.
    ///   - shouldRetry: Called with each thrown error to decide whether it is worth retrying.
    ///
    /// - Returns: A `RetryPolicy` with an exponentially growing delay between attempts.
    ///
    public static func exponentialBackoff(
        _ maxAttempts: Int,
        baseDelay: UnitTime = .seconds(1),
        multiplier: Int = 2,
        maxDelay: UnitTime = .seconds(30),
        shouldRetry: @escaping @Sendable (Error) -> Bool = { _ in true }
    ) -> RetryPolicy {
        .init(maxAttempts: maxAttempts, shouldRetry: shouldRetry) { attempt in
            var delay = baseDelay
            var remainingDoublings = attempt - 1

            while remainingDoublings > 0, delay < maxDelay {
                delay = delay * multiplier
                remainingDoublings -= 1
            }

            return min(delay, maxDelay)
        }
    }
}
