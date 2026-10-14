//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin) && canImport(CFNetwork)

import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.URLComponents
import struct Foundation.DispatchTime
#endif

extension Internals {

    /// Caches `Internals.PACEvaluator.evaluate(...)`'s result per `(scriptURL, targetURL)` pair,
    /// so a burst of requests to the same host doesn't each pay for a fresh network fetch and
    /// JavaScript evaluation of the same PAC script: the cost the original "PAC is skipped
    /// entirely" version of this resolver was written specifically to avoid paying per request.
    ///
    /// The target of a secure URL (`https`, `wss`) is reduced to its origin before it is cached
    /// or evaluated, which is what browsers hand a PAC script for those schemes: the path and
    /// query of a secure URL are not available to a proxy, and often carry tokens a PAC script
    /// has no business seeing. Requests that differ only in path or query (pagination, signed
    /// URLs) then share one evaluation instead of each paying for a thread and a script run.
    /// Plain `http` URLs keep their full address, since a script may legitimately route on it.
    ///
    /// At most `maximumConcurrentEvaluations` evaluations run at once, because each one holds a
    /// dedicated thread (see `Internals.PACEvaluator`); the rest wait for a slot.
    package actor PACProxyCache {

        // MARK: - Internal static properties

        package static let shared = PACProxyCache()

        // MARK: - Private static properties

        /// How long an entry the script answered is trusted before being re-evaluated. A failed
        /// evaluation is remembered for `failureLifetime` instead.
        /// Matches `Internals.Storage`/`Internals.ClientManager`'s own default lifetime.
        private static let lifetime: Int64 = 5 * 60 * 1_000_000_000

        /// How long a failed evaluation (the script could not be fetched or run) is remembered.
        /// Short, unlike `lifetime`: a script that answers is a stable fact about the network,
        /// but a failure is usually a dropped connection or a slow server, and remembering it
        /// for minutes would send every request in that window around the proxy the script
        /// would have chosen. It is not zero, because an unreachable PAC server otherwise makes
        /// every request wait out the whole evaluation timeout.
        package static let failureLifetime: Int64 = Internals.SystemProxyResolver.PACOptions.defaultFailureLifetime

        /// Bounds one evaluation's fetch-and-execute time. Without this, an unreachable PAC
        /// server would hang every request routed through it, not just the first. 30s, not a
        /// tighter bound: a PAC file is commonly hosted on a slow internal server reached over a
        /// real (if sluggish) corporate network, and this only ever costs one request's worth of
        /// latency per `lifetime` window thanks to the cache above it.
        package static let evaluationTimeout: Double = Internals.SystemProxyResolver.PACOptions.defaultEvaluationTimeout

        /// A ceiling, not a working limit, same rationale as `Internals.Storage.maximumCount`.
        /// `storage` is keyed by `(scriptURL, targetURL)`, and entries only expire logically
        /// (`isExpired`, checked on read); nothing sweeps them out on its own. Without a ceiling,
        /// a workload that hits many distinct target URLs under one PAC script (a feed of
        /// distinct image URLs, say) could grow this table for the lifetime of the process.
        package static let maximumCount = 256

        /// Evaluations allowed to hold a thread at the same time. A burst of distinct `http`
        /// URLs would otherwise start one thread each, up to 30s per thread.
        package static let maximumConcurrentEvaluations = 8

        // MARK: - Internal properties

        /// `storage.count`, exposed for tests: verifying eviction black-box (query an old key
        /// again and check for a fresh evaluation) would mean paying for hundreds of real PAC
        /// evaluations just to exceed a default-sized cache.
        package var count: Int {
            storage.count
        }

        /// How many evaluations this instance has actually started, exposed for tests. Whether
        /// concurrent misses for the same key share one evaluation isn't observable from outside
        /// through connection or thread counts alone: `CFNetworkExecuteProxyAutoConfigurationURL`
        /// caches a script's fetched content internally, and `inFlight`'s own count can only ever
        /// be 0 or 1 for a given key. A monotonic count of genuinely-started evaluations is what a
        /// test actually needs.
        package private(set) var evaluationCount = 0

        /// The most evaluations that ever ran at once, exposed for tests.
        package private(set) var peakConcurrentEvaluations = 0

        // MARK: - Private properties

        private let maximumCount: Int
        private let maximumConcurrentEvaluations: Int
        private let failureLifetime: Int64
        private let now: @Sendable () -> UInt64
        private let evaluate: @Sendable (URL, URL, Double) async throws -> Internals.Proxy?

        private var runningEvaluations = 0
        private var waitingForSlot: [CheckedContinuation<Void, Never>] = []

        private var storage: [Key: Entry] = [:]

        /// The last answer each key's script gave, kept apart from `storage` because an entry there
        /// is replaced by a failure and dropped when it is old, and the answer is what stands in for
        /// the script when it cannot be asked. Never replaced by a failure. For the life of the
        /// process and no longer: nothing here is written to disk.
        private var lastAnswers: [Key: LastAnswer] = [:]

        /// One evaluation per key in flight at a time. `proxy(forScriptURL:targetURL:)` awaits
        /// `Internals.PACEvaluator.evaluate(...)`, a genuine suspension point, so a burst of
        /// concurrent requests to the same host (a screenful of images loading at once, say)
        /// shares the one evaluation already in progress instead of each opening its own
        /// dedicated `Thread` in `Internals.PACEvaluator`.
        private var inFlight: [Key: _Concurrency.Task<Evaluation, Never>] = [:]

        // MARK: - Inits

        /// `package`, not `private`: `.shared` is what `Internals.SystemProxyResolver` actually
        /// uses, but tests want their own isolated instance rather than risking cross-test cache
        /// pollution through the process-wide singleton. `maximumCount` likewise defaults to the
        /// real ceiling but is overridable, so a test can exercise eviction with a handful of
        /// entries instead of needing hundreds of real PAC evaluations to exceed it.
        ///
        /// `evaluate` defaults to the real `Internals.PACEvaluator`; a test replaces it to control
        /// when an evaluation finishes and to see what it was asked. `now` is the monotonic clock
        /// entries are aged by, in nanoseconds; a test replaces it to move time without waiting.
        package init(
            maximumCount: Int = PACProxyCache.maximumCount,
            maximumConcurrentEvaluations: Int = PACProxyCache.maximumConcurrentEvaluations,
            failureLifetime: Int64 = PACProxyCache.failureLifetime,
            now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
            evaluate: @escaping @Sendable (URL, URL, Double) async throws -> Internals.Proxy? = {
                try await Internals.PACEvaluator.evaluate(scriptURL: $0, targetURL: $1, timeout: $2)
            }
        ) {
            self.maximumCount = maximumCount
            self.maximumConcurrentEvaluations = max(maximumConcurrentEvaluations, 1)
            self.failureLifetime = failureLifetime
            self.now = now
            self.evaluate = evaluate
        }

        // MARK: - Internal methods

        /// The proxy `scriptURL`'s PAC script resolves `targetURL` to, or `nil` for a direct
        /// connection, including when evaluation itself fails (a stale/misconfigured PAC file,
        /// an unreachable PAC server, a script that throws).
        ///
        /// Failing safe to direct is the same choice
        /// `Internals.SystemProxyResolver.firstResolution(in:)` already makes for any other
        /// proxy-list entry it can't parse. A caller that needs to tell a failure from a script
        /// that answered "direct" asks ``resolution(forScriptURL:targetURL:)`` instead.
        package func proxy(forScriptURL scriptURL: URL, targetURL: URL) async -> Internals.Proxy? {
            guard case .answered(let proxy) = await resolution(forScriptURL: scriptURL, targetURL: targetURL) else {
                return nil
            }

            return proxy
        }

        /// What `scriptURL`'s PAC script comes to for `targetURL`: the proxy it answered (`nil`
        /// for "direct"), the failure when it could not be asked, or that the caller was
        /// cancelled while it waited.
        ///
        /// A failure is remembered for `failureLifetime` only, so a script that was briefly
        /// unreachable is asked again soon, and a script that answers is kept for `lifetime`.
        /// Everyone who asks within that window gets the same failure, at once, instead of each
        /// waiting out the evaluation. A failure carries the last answer the script gave for this
        /// key, if it ever did.
        ///
        /// - Parameters:
        ///   - evaluationTimeout: How long an evaluation this call starts may take, in seconds.
        ///   Callers that arrive while it runs share it, and so share this timeout.
        ///   - failureLifetime: How long a failure of an evaluation this call starts is
        ///   remembered, in nanoseconds. `nil` is the cache's own.
        package func resolution(
            forScriptURL scriptURL: URL,
            targetURL: URL,
            evaluationTimeout: Double = PACProxyCache.evaluationTimeout,
            failureLifetime: Int64? = nil
        ) async -> Internals.PACResolution {
            let targetURL = Self.evaluationTarget(for: targetURL)
            let key = Key(scriptURL: scriptURL, targetURL: targetURL)

            if let entry = storage[key], !isExpired(entry) {
                return withLastKnown(entry.resolution, key: key)
            }

            let task: _Concurrency.Task<Evaluation, Never>

            if let inFlightTask = inFlight[key] {
                task = inFlightTask
            } else {
                evaluationCount += 1

                let evaluate = evaluate
                let failureLifetime = failureLifetime ?? self.failureLifetime

                let newTask = _Concurrency.Task<Evaluation, Never> {
                    await self.acquireEvaluationSlot()

                    let evaluation: Evaluation

                    do {
                        evaluation = Evaluation(
                            resolution: .answered(try await evaluate(scriptURL, targetURL, evaluationTimeout))
                        )
                    } catch {
                        evaluation = Evaluation(resolution: .failed(Self.failure(from: error), lastKnown: nil))
                    }

                    await self.releaseEvaluationSlot()

                    // Recorded here, by the evaluation itself, and not by a task that waits for it:
                    // this task is already detached from any one caller's lifetime (it runs to the
                    // end whether or not the call that started it is still being awaited), and a
                    // caller that sees its result must find the entry already stored and
                    // `inFlight` already cleared. Left to a second task, that was a window in which
                    // a finished evaluation was still the one in flight, and a request that came in
                    // after its failure window (or after the clock was moved, in a test) was given
                    // the old result instead of asking the script again.
                    await self.finishEvaluation(key: key, evaluation: evaluation, failureLifetime: failureLifetime)

                    return evaluation
                }
                inFlight[key] = newTask
                task = newTask
            }

            // `await task.value` alone does not observe *this call's own* task cancellation: an
            // unstructured `Task`'s `.value` runs to completion regardless of what the awaiting
            // side does, so a caller cancelled while `PACEvaluator`'s up-to-30s timeout is still
            // running would otherwise stay suspended for the rest of it, which is the hang this
            // cache exists to bound to once per `lifetime` window, not once per caller. Racing it
            // against cancellation lets a cancelled caller fail safe to direct (`nil`) immediately
            // instead, without disturbing the shared evaluation other, still-live callers for the
            // same key are waiting on.
            return withLastKnown(await Self.awaitingCancellably(task), key: key)
        }

        /// A failure with the last answer the script gave for `key` attached, so whoever decides
        /// what the failure does can fall back on it.
        private func withLastKnown(_ resolution: Internals.PACResolution, key: Key) -> Internals.PACResolution {
            guard case .failed(let failure, _) = resolution else {
                return resolution
            }

            let lastKnown = lastAnswers[key].map {
                Internals.PACLastKnownAnswer(proxy: $0.proxy, ageNanoseconds: now() &- $0.answeredAt)
            }

            return .failed(failure, lastKnown: lastKnown)
        }

        private func acquireEvaluationSlot() async {
            if runningEvaluations < maximumConcurrentEvaluations {
                runningEvaluations += 1
                peakConcurrentEvaluations = max(peakConcurrentEvaluations, runningEvaluations)
                return
            }

            // The slot is handed over by `releaseEvaluationSlot()` without going through
            // `runningEvaluations`, which is why it is not incremented again here.
            await withCheckedContinuation { waitingForSlot.append($0) }
        }

        private func releaseEvaluationSlot() {
            if waitingForSlot.isEmpty {
                runningEvaluations -= 1
            } else {
                waitingForSlot.removeFirst().resume()
            }
        }

        /// What a PAC script is asked about for `url`: the origin only, for a secure scheme.
        private static func evaluationTarget(for url: URL) -> URL {
            guard
                let scheme = url.scheme?.lowercased(),
                scheme == "https" || scheme == "wss",
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            else {
                return url
            }

            components.scheme = scheme
            components.host = components.host?.lowercased()
            components.user = nil
            components.password = nil
            components.path = "/"
            components.query = nil
            components.fragment = nil

            return components.url ?? url
        }

        private func finishEvaluation(key: Key, evaluation: Evaluation, failureLifetime: Int64) {
            inFlight[key] = nil
            let failed: Bool

            switch evaluation.resolution {
            case .answered(let proxy):
                failed = false
                lastAnswers[key] = LastAnswer(proxy: proxy, answeredAt: now())

            case .failed, .cancelled:
                failed = true
            }

            storage[key] = Entry(
                resolution: evaluation.resolution,
                readAt: now(),
                lifetime: failed ? failureLifetime : Self.lifetime
            )
            evictIfNeeded()
            evictLastAnswersIfNeeded()
        }

        private static func awaitingCancellably(
            _ task: _Concurrency.Task<Evaluation, Never>
        ) async -> Internals.PACResolution {
            let box = PACCacheAwaitBox()

            return await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Internals.PACResolution, Never>) in
                    box.attach(continuation)

                    _Concurrency.Task {
                        box.resolve(returning: await task.value.resolution)
                    }
                }
            } onCancel: {
                box.cancel()
            }
        }

        /// What the evaluator's error comes to for a caller: it timed out, or it did not work.
        private static func failure(from error: Swift.Error) -> Internals.PACEvaluationFailure {
            switch error {
            case let error as Internals.PACEvaluator.Error:
                switch error {
                case .timedOut:
                    return .init(reason: .timedOut)

                case .executionFailed(let details):
                    return .init(reason: .failed, details: details)
                }

            default:
                return .init(reason: .failed, details: String(describing: error))
            }
        }

        // MARK: - Private methods

        private func isExpired(_ entry: Entry) -> Bool {
            now() - entry.readAt > entry.lifetime
        }

        /// Brings `storage` back under `maximumCount`, oldest first. Drops down to three
        /// quarters rather than removing one entry per insert, the same batching
        /// `Internals.Storage._evictIfNeeded()` uses and for the same reason: sorting is
        /// linearithmic, so evicting a single entry per call would make a table sitting at the
        /// ceiling pay a full scan on every miss.
        private func evictIfNeeded() {
            guard storage.count > maximumCount else {
                return
            }

            let target = max(maximumCount - (maximumCount / 4), 1)
            let excess = storage.count - target

            let oldest =
                storage
                .sorted { $0.value.readAt < $1.value.readAt }
                .prefix(excess)

            for (key, _) in oldest {
                storage[key] = nil
            }
        }

        /// Brings `lastAnswers` back under `maximumCount` the way `evictIfNeeded()` does for
        /// `storage`: oldest first, down to three quarters.
        private func evictLastAnswersIfNeeded() {
            guard lastAnswers.count > maximumCount else {
                return
            }

            let target = max(maximumCount - (maximumCount / 4), 1)
            let excess = lastAnswers.count - target

            let oldest =
                lastAnswers
                .sorted { $0.value.answeredAt < $1.value.answeredAt }
                .prefix(excess)

            for (key, _) in oldest {
                lastAnswers[key] = nil
            }
        }

        // MARK: - Private nested types

        private struct LastAnswer {
            let proxy: Internals.Proxy?
            // Monotonic, like `Entry.readAt`.
            let answeredAt: UInt64
        }

        private struct Key: Hashable {
            let scriptURL: URL
            let targetURL: URL
        }

        /// What one evaluation came to. A failure (the script could not be fetched or run) stays
        /// apart from a script that answered "direct", which is `.answered(nil)`.
        private struct Evaluation: Sendable {
            let resolution: Internals.PACResolution
        }

        private struct Entry {
            let resolution: Internals.PACResolution
            // Monotonic, not wall clock: same rationale as `Internals.Storage`/
            // `Internals.ClientManager`: a `Date`-based deadline moves if the user or NTP moves
            // the system clock, and this must not advance while the device is suspended either
            // way.
            let readAt: UInt64
            let lifetime: Int64
        }
    }
}

/// Lets `PACProxyCache.awaitingCancellably(_:)` race an unstructured `Task`'s completion against
/// the *awaiting* task's own cancellation, resuming with `nil` (fail safe to direct, same as any
/// other unresolvable proxy-list entry) on whichever happens first. Exactly one of
/// `attach`/`resolve`/`cancel` ever wins the resume; the others become no-ops.
private final class PACCacheAwaitBox: @unchecked Sendable {

    // MARK: - Private properties

    private let lock = Lock()
    private var continuation: CheckedContinuation<Internals.PACResolution, Never>?
    private var isCancelled = false
    private var isResumed = false

    // MARK: - Internal methods

    /// Registers `continuation` as the one `resolve`/`cancel` should answer, unless `cancel()`
    /// already ran, in which case this resumes it immediately instead, since there is nothing
    /// left to wait on.
    func attach(_ continuation: CheckedContinuation<Internals.PACResolution, Never>) {
        let resumeNow: Bool = lock.withLock {
            guard !isResumed else { return false }

            if isCancelled {
                isResumed = true
                return true
            }

            self.continuation = continuation
            return false
        }

        if resumeNow {
            continuation.resume(returning: .cancelled)
        }
    }

    func resolve(returning value: Internals.PACResolution) {
        let toResume: CheckedContinuation<Internals.PACResolution, Never>? = lock.withLock {
            guard !isResumed, let continuation else { return nil }
            isResumed = true
            self.continuation = nil
            return continuation
        }

        toResume?.resume(returning: value)
    }

    func cancel() {
        let toResume: CheckedContinuation<Internals.PACResolution, Never>? = lock.withLock {
            isCancelled = true

            guard !isResumed, let continuation else { return nil }
            isResumed = true
            self.continuation = nil
            return continuation
        }

        toResume?.resume(returning: .cancelled)
    }
}

#endif
