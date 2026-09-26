//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)
import AsyncHTTPClient
#endif

extension Internals {

    /// Portable mirror of `HTTPClient.Configuration.ConnectionPool`, matched field for field:
    /// this configuration is shared by both executors, and `Internals.ClientManager` uses it
    /// (via `Internals.Session.Configuration`'s own `Equatable`) as part of its pooled-client
    /// cache key, so it has to exist regardless of whether NIO does.
    package struct ConnectionPool: Sendable, Hashable {

        // MARK: - Internal properties

        /// Nanoseconds, matching `UnitTime.nanoseconds` (`RequestDL`'s public unit of time),
        /// same convention as `Internals.Timeout`. Defaults to `AsyncHTTPClient`'s own default
        /// (60 seconds), so a configuration nobody touched behaves the same as calling
        /// `AsyncHTTPClient` directly.
        package var idleTimeout: Int64 = 60_000_000_000

        /// `nil` means untouched: each transport keeps its own native default (AsyncHTTPClient's
        /// 8, `URLSessionConfiguration`'s 6) rather than having one of them imposed on the other.
        ///
        /// Optional, unlike the other fields here, specifically so `.urlSession` can tell an
        /// explicit `Session.maximumConnectionsPerHost(_:)` apart from a caller who never asked:
        /// `URLSessionConfiguration.httpMaximumConnectionsPerHost` is a plain `Int` with no
        /// "unset" value of its own, so writing this out unconditionally would silently retune
        /// every session that never set it.
        package var concurrentHTTP1ConnectionsPerHostSoftLimit: Int?

        package var retryConnectionEstablishment: Bool = true

        package var preWarmedHTTP1ConnectionCount: Int = 0

        // MARK: - Inits

        package init() {}

        // MARK: - Internal methods

        #if canImport(NIOCore)
        package func build() -> HTTPClient.Configuration.ConnectionPool {
            var pool = HTTPClient.Configuration.ConnectionPool()
            pool.idleTimeout = .nanoseconds(idleTimeout)
            if let concurrentHTTP1ConnectionsPerHostSoftLimit {
                pool.concurrentHTTP1ConnectionsPerHostSoftLimit = concurrentHTTP1ConnectionsPerHostSoftLimit
            }
            pool.retryConnectionEstablishment = retryConnectionEstablishment
            pool.preWarmedHTTP1ConnectionCount = preWarmedHTTP1ConnectionCount
            return pool
        }
        #endif
    }
}
