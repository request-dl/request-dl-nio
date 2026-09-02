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
    /// JavaScript evaluation of the same PAC script -- the cost the original "PAC is skipped
    /// entirely" version of this resolver was written specifically to avoid paying per request.
    package actor PACProxyCache {

        // MARK: - Internal static properties

        package static let shared = PACProxyCache()

        // MARK: - Private static properties

        /// How long a resolved (or failed-to-resolve) entry is trusted before being re-evaluated.
        /// Matches `Internals.Storage`/`Internals.ClientManager`'s own default lifetime.
        private static let lifetime: Int64 = 5 * 60 * 1_000_000_000

        /// Bounds one evaluation's fetch-and-execute time -- without this, an unreachable PAC
        /// server would hang every request routed through it, not just the first.
        private static let evaluationTimeout: Double = 10

        // MARK: - Private properties

        private var storage: [Key: Entry] = [:]

        // MARK: - Inits

        /// `package`, not `private`: `.shared` is what `Internals.SystemProxyResolver` actually
        /// uses, but tests want their own isolated instance rather than risking cross-test cache
        /// pollution through the process-wide singleton.
        package init() {}

        // MARK: - Internal methods

        /// The proxy `scriptURL`'s PAC script resolves `targetURL` to, or `nil` for a direct
        /// connection -- including when evaluation itself fails (a stale/misconfigured PAC file,
        /// an unreachable PAC server, a script that throws): failing safe to direct is the same
        /// choice `Internals.SystemProxyResolver.firstResolution(in:)` already makes for any other
        /// proxy-list entry it can't parse.
        package func proxy(forScriptURL scriptURL: URL, targetURL: URL) async -> Internals.Proxy? {
            let key = Key(scriptURL: scriptURL, targetURL: targetURL)

            if let entry = storage[key], !isExpired(entry) {
                return entry.proxy
            }

            let resolved: Internals.Proxy?

            do {
                resolved = try await Internals.PACEvaluator.evaluate(
                    scriptURL: scriptURL,
                    targetURL: targetURL,
                    timeout: Self.evaluationTimeout
                )
            } catch {
                resolved = nil
            }

            storage[key] = Entry(
                proxy: resolved,
                readAt: DispatchTime.now().uptimeNanoseconds
            )

            return resolved
        }

        // MARK: - Private methods

        private func isExpired(_ entry: Entry) -> Bool {
            DispatchTime.now().uptimeNanoseconds - entry.readAt > Self.lifetime
        }

        // MARK: - Private nested types

        private struct Key: Hashable {
            let scriptURL: URL
            let targetURL: URL
        }

        private struct Entry {
            let proxy: Internals.Proxy?
            // Monotonic, not wall clock -- same rationale as `Internals.Storage`/
            // `Internals.ClientManager`: a `Date`-based deadline moves if the user or NTP moves
            // the system clock, and this must not advance while the device is suspended either
            // way.
            let readAt: UInt64
        }
    }
}

#endif
