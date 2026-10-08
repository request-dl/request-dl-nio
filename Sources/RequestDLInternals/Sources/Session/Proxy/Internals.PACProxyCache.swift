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

        /// How long a resolved (or failed-to-resolve) entry is trusted before being re-evaluated.
        /// Matches `Internals.Storage`/`Internals.ClientManager`'s own default lifetime.
        private static let lifetime: Int64 = 5 * 60 * 1_000_000_000

        /// Bounds one evaluation's fetch-and-execute time. Without this, an unreachable PAC
        /// server would hang every request routed through it, not just the first. 30s, not a
        /// tighter bound: a PAC file is commonly hosted on a slow internal server reached over a
        /// real (if sluggish) corporate network, and this only ever costs one request's worth of
        /// latency per `lifetime` window thanks to the cache above it.
        private static let evaluationTimeout: Double = 30

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
        private let evaluate: @Sendable (URL, URL, Double) async throws -> Internals.Proxy?

        private var runningEvaluations = 0
        private var waitingForSlot: [CheckedContinuation<Void, Never>] = []

        private var storage: [Key: Entry] = [:]

        /// One evaluation per key in flight at a time. `proxy(forScriptURL:targetURL:)` awaits
        /// `Internals.PACEvaluator.evaluate(...)`, a genuine suspension point, so a burst of
        /// concurrent requests to the same host (a screenful of images loading at once, say)
        /// shares the one evaluation already in progress instead of each opening its own
        /// dedicated `Thread` in `Internals.PACEvaluator`.
        private var inFlight: [Key: _Concurrency.Task<Internals.Proxy?, Never>] = [:]

        // MARK: - Inits

        /// `package`, not `private`: `.shared` is what `Internals.SystemProxyResolver` actually
        /// uses, but tests want their own isolated instance rather than risking cross-test cache
        /// pollution through the process-wide singleton. `maximumCount` likewise defaults to the
        /// real ceiling but is overridable, so a test can exercise eviction with a handful of
        /// entries instead of needing hundreds of real PAC evaluations to exceed it.
        ///
        /// `evaluate` defaults to the real `Internals.PACEvaluator`; a test replaces it to control
        /// when an evaluation finishes and to see what it was asked.
        package init(
            maximumCount: Int = PACProxyCache.maximumCount,
            maximumConcurrentEvaluations: Int = PACProxyCache.maximumConcurrentEvaluations,
            evaluate: @escaping @Sendable (URL, URL, Double) async throws -> Internals.Proxy? = {
                try await Internals.PACEvaluator.evaluate(scriptURL: $0, targetURL: $1, timeout: $2)
            }
        ) {
            self.maximumCount = maximumCount
            self.maximumConcurrentEvaluations = max(maximumConcurrentEvaluations, 1)
            self.evaluate = evaluate
        }

        // MARK: - Internal methods

        /// The proxy `scriptURL`'s PAC script resolves `targetURL` to, or `nil` for a direct
        /// connection, including when evaluation itself fails (a stale/misconfigured PAC file,
        /// an unreachable PAC server, a script that throws).
        ///
        /// Failing safe to direct is the same choice
        /// `Internals.SystemProxyResolver.firstResolution(in:)` already makes for any other
        /// proxy-list entry it can't parse.
        package func proxy(forScriptURL scriptURL: URL, targetURL: URL) async -> Internals.Proxy? {
            let targetURL = Self.evaluationTarget(for: targetURL)
            let key = Key(scriptURL: scriptURL, targetURL: targetURL)

            if let entry = storage[key], !isExpired(entry) {
                return entry.proxy
            }

            let task: _Concurrency.Task<Internals.Proxy?, Never>

            if let inFlightTask = inFlight[key] {
                task = inFlightTask
            } else {
                evaluationCount += 1

                let evaluate = evaluate

                let newTask = _Concurrency.Task<Internals.Proxy?, Never> {
                    await self.acquireEvaluationSlot()

                    let proxy: Internals.Proxy?

                    do {
                        proxy = try await evaluate(scriptURL, targetURL, Self.evaluationTimeout)
                    } catch {
                        proxy = nil
                    }

                    await self.releaseEvaluationSlot()
                    return proxy
                }
                inFlight[key] = newTask
                task = newTask

                // Detached from any one caller's lifetime on purpose: this records the result for
                // whoever asks next (this key's cache entry, and any other concurrent caller
                // sharing `inFlight[key]`) regardless of whether the specific call that started the
                // evaluation is itself still being awaited below, since it may have already
                // returned early after its own task was cancelled.
                _Concurrency.Task { [weak self] in
                    let resolved = await newTask.value
                    await self?.finishEvaluation(key: key, resolved: resolved)
                }
            }

            // `await task.value` alone does not observe *this call's own* task cancellation: an
            // unstructured `Task`'s `.value` runs to completion regardless of what the awaiting
            // side does, so a caller cancelled while `PACEvaluator`'s up-to-30s timeout is still
            // running would otherwise stay suspended for the rest of it, which is the hang this
            // cache exists to bound to once per `lifetime` window, not once per caller. Racing it
            // against cancellation lets a cancelled caller fail safe to direct (`nil`) immediately
            // instead, without disturbing the shared evaluation other, still-live callers for the
            // same key are waiting on.
            return await Self.awaitingCancellably(task)
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

        private func finishEvaluation(key: Key, resolved: Internals.Proxy?) {
            inFlight[key] = nil
            storage[key] = Entry(
                proxy: resolved,
                readAt: DispatchTime.now().uptimeNanoseconds
            )
            evictIfNeeded()
        }

        private static func awaitingCancellably(
            _ task: _Concurrency.Task<Internals.Proxy?, Never>
        ) async -> Internals.Proxy? {
            let box = PACCacheAwaitBox()

            return await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Internals.Proxy?, Never>) in
                    box.attach(continuation)

                    _Concurrency.Task {
                        box.resolve(returning: await task.value)
                    }
                }
            } onCancel: {
                box.cancel()
            }
        }

        // MARK: - Private methods

        private func isExpired(_ entry: Entry) -> Bool {
            DispatchTime.now().uptimeNanoseconds - entry.readAt > Self.lifetime
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

        // MARK: - Private nested types

        private struct Key: Hashable {
            let scriptURL: URL
            let targetURL: URL
        }

        private struct Entry {
            let proxy: Internals.Proxy?
            // Monotonic, not wall clock: same rationale as `Internals.Storage`/
            // `Internals.ClientManager`: a `Date`-based deadline moves if the user or NTP moves
            // the system clock, and this must not advance while the device is suspended either
            // way.
            let readAt: UInt64
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
    private var continuation: CheckedContinuation<Internals.Proxy?, Never>?
    private var isCancelled = false
    private var isResumed = false

    // MARK: - Internal methods

    /// Registers `continuation` as the one `resolve`/`cancel` should answer, unless `cancel()`
    /// already ran, in which case this resumes it immediately instead, since there is nothing
    /// left to wait on.
    func attach(_ continuation: CheckedContinuation<Internals.Proxy?, Never>) {
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
            continuation.resume(returning: nil)
        }
    }

    func resolve(returning value: Internals.Proxy?) {
        let toResume: CheckedContinuation<Internals.Proxy?, Never>? = lock.withLock {
            guard !isResumed, let continuation else { return nil }
            isResumed = true
            self.continuation = nil
            return continuation
        }

        toResume?.resume(returning: value)
    }

    func cancel() {
        let toResume: CheckedContinuation<Internals.Proxy?, Never>? = lock.withLock {
            isCancelled = true

            guard !isResumed, let continuation else { return nil }
            isResumed = true
            self.continuation = nil
            return continuation
        }

        toResume?.resume(returning: nil)
    }
}

#endif
