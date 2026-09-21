//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin) && canImport(CFNetwork)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.DispatchTime
#endif

extension Internals {

    /// Caches `Internals.PACEvaluator.evaluate(...)`'s result per `(scriptURL, targetURL)` pair,
    /// so a burst of requests to the same host doesn't each pay for a fresh network fetch and
    /// JavaScript evaluation of the same PAC script: the cost the original "PAC is skipped
    /// entirely" version of this resolver was written specifically to avoid paying per request.
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

        // MARK: - Private properties

        private let maximumCount: Int

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
        package init(maximumCount: Int = PACProxyCache.maximumCount) {
            self.maximumCount = maximumCount
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
            let key = Key(scriptURL: scriptURL, targetURL: targetURL)

            if let entry = storage[key], !isExpired(entry) {
                return entry.proxy
            }

            if let inFlightTask = inFlight[key] {
                return await inFlightTask.value
            }

            evaluationCount += 1

            let task = _Concurrency.Task<Internals.Proxy?, Never> {
                do {
                    return try await Internals.PACEvaluator.evaluate(
                        scriptURL: scriptURL,
                        targetURL: targetURL,
                        timeout: Self.evaluationTimeout
                    )
                } catch {
                    return nil
                }
            }
            inFlight[key] = task

            let resolved = await task.value

            inFlight[key] = nil
            storage[key] = Entry(
                proxy: resolved,
                readAt: DispatchTime.now().uptimeNanoseconds
            )
            evictIfNeeded()

            return resolved
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

#endif
