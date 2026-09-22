//
// See LICENSE for this package's licensing information.
//

// Only used by Internals.ClientManager+NIO.swift, itself NIO-only.
#if canImport(NIOCore)

import NIOCore
import SwiftAsyncStream

extension Internals {

    /// A handle on one event-loop group, and the thing that decides when that group's threads
    /// are retired.
    ///
    /// `EventLoopGroupManager`'s table is a *cache*, not an owner. An entry can be dropped from
    /// it — evicted for capacity, or superseded — while clients built on that group are still
    /// running requests over it. Shutting the group down at that moment pulls the event loops out
    /// from under live connections, and an `AsyncHTTPClient.HTTPClient` on a dead group can never
    /// complete its own `shutdown()`: NIO reports the unfulfilled promise as a leaked promise and
    /// traps the process.
    ///
    /// So the group outlives the cache entry and is retired here instead, once the last holder of
    /// this token — the manager while it is cached, plus every `Internals.Client` built on it —
    /// has let go.
    package final class EventLoopGroupToken: @unchecked Sendable {

        // MARK: - Internal properties

        package let group: EventLoopGroup

        // MARK: - Private properties

        /// `false` for a group this package only borrows: NIO's process-wide singletons and a
        /// group the caller constructed and handed in through `Session.init(_:)`. Shutting either
        /// of those down would take every unrelated user of the same group with it. See
        /// `SessionProvider.createsGroup`.
        private let shutsDownOnRelease: Bool

        /// Signalled once the group has finished shutting down, so the retirement is observable
        /// instead of having to be raced. `nil` for a borrowed group, which never retires.
        private let shutdowns: Internals.PendingTasks?

        // MARK: - Inits

        init(group: EventLoopGroup, shutsDownOnRelease: Bool, shutdowns: Internals.PendingTasks?) {
            self.group = group
            self.shutsDownOnRelease = shutsDownOnRelease
            self.shutdowns = shutdowns
        }

        deinit {
            guard shutsDownOnRelease else {
                return
            }

            // `group` is captured, not `self`, and the operation keeps it alive until the
            // shutdown finishes: same discipline `Internals.Client.deinit` uses for its own
            // `HTTPClient`.
            guard let shutdowns else {
                group.shutdownGracefully { _ in }
                return
            }

            shutdowns.run { [group] in try? await group.shutdownGracefully() }
        }
    }

    package final class EventLoopGroupManager: @unchecked Sendable {

        // MARK: - Internal static properties

        package static let shared = EventLoopGroupManager()

        /// A ceiling on how many event-loop groups may be *cached* at once.
        ///
        /// Same shape and same reason as `Internals.Storage.maximumCount`: a ceiling, not a
        /// working limit, so that a workload producing a great many distinct session identifiers
        /// cannot grow the table without bound. It is set far below `Storage`'s, because an entry
        /// here stands for a whole set of OS threads rather than a single cached value —
        /// `Session(_:numberOfThreads:)` with a fresh identifier per request otherwise leaked a
        /// `MultiThreadedEventLoopGroup`, threads and all, for the life of the process.
        ///
        /// Evicting is never the same thing as shutting down: what actually retires a group is
        /// the last `EventLoopGroupToken` for it going away. See that type.
        package static let maximumCount = 32

        // MARK: - Private static properties

        /// Flags a `provider(_:with:)` that is still running after 15s. Development builds
        /// only. See `AsyncLock.Watchdog`.
        #if DEBUG
        private static let watchdog: AsyncLock.Watchdog? = .init(seconds: 15) {
            Internals.assertionFailure($0)
        }
        #else
        private static let watchdog: AsyncLock.Watchdog? = nil
        #endif

        // MARK: - Internal properties

        /// How many groups are currently cached. Bookkeeping only; nothing in the resolution
        /// path reads it.
        package var count: Int {
            get async {
                await lock.withLock { _groups.count }
            }
        }

        // MARK: - Private properties

        private let lock = AsyncLock(watchdog: watchdog)
        private let maximumCount: Int

        /// The group shutdowns started but not yet finished.
        ///
        /// A retirement happens whenever the last token is released, which is nobody's call in
        /// particular, so without something to join them "this group is gone" would only ever be
        /// observable by racing the group's own API. `PendingTasks` is the package's
        /// `AsyncSignal`-backed way to wait on exactly that, already used for cache writes.
        private let shutdowns = Internals.PendingTasks(priority: .utility)

        // MARK: - Unsafe properties

        private var _groups = [String: Entry]()
        private var _sequence: UInt64 = 0

        // MARK: - Inits

        package init(maximumCount: Int = EventLoopGroupManager.maximumCount) {
            precondition(maximumCount >= 1, "EventLoopGroupManager needs room for at least one group")
            self.maximumCount = maximumCount
        }

        // MARK: - Internal methods

        /// Returns the event loop group for a provider, creating it the first time.
        ///
        /// - Returns: A token the caller must hold for as long as it uses the group, not the bare
        /// group: that is what keeps the group alive past its cache entry. See
        /// ``EventLoopGroupToken``.
        ///
        /// - Important: Must not hop through `Task.detached(priority: .background)`.
        /// `Task.detached` does not inherit priority, so if the caller awaits the result, a
        /// `.userInitiated` request ends up waiting on a `.background` task: a textbook priority
        /// inversion, right on the path that has to run before any request goes out. Background
        /// is also the first thing the system defers under thermal pressure or Low Power Mode,
        /// which is exactly when a request should not be stalling.
        ///
        /// If a future change needs that hop to work around something, that something needs a
        /// different answer.
        package func provider(
            _ sessionProvider: SessionProvider,
            with options: SessionProviderOptions
        ) async -> EventLoopGroupToken {
            await lock.withLock {
                let sessionProviderID = sessionProvider.uniqueIdentifier(with: options)

                _sequence &+= 1

                if let existing = _groups[sessionProviderID] {
                    // Reinserting refreshes the entry's position in the eviction order, so a
                    // group that keeps being asked for keeps moving away from the front of it.
                    _groups[sessionProviderID] = Entry(token: existing.token, usedAt: _sequence)
                    return existing.token
                }

                let createsGroup = sessionProvider.createsGroup

                let token = EventLoopGroupToken(
                    group: sessionProvider.group(with: options),
                    shutsDownOnRelease: createsGroup,
                    shutdowns: createsGroup ? shutdowns : nil
                )

                _groups[sessionProviderID] = Entry(token: token, usedAt: _sequence)
                _evictIfNeeded()

                return token
            }
        }

        /// Suspends until every group retirement started so far has finished.
        ///
        /// A retirement runs detached from whoever released the last token, so without this "the
        /// group is gone" is only observable by poking at the group itself and hoping the timing
        /// works out.
        package func waitUntilShutdownsComplete() async {
            await shutdowns.waitUntilIdle()
        }

        // MARK: - Unsafe methods

        /// Brings `_groups` back under ``maximumCount``, least recently asked for first.
        ///
        /// Drops to three quarters of the ceiling in one pass rather than evicting one entry per
        /// insert, for the same reason `Internals.Storage._evictIfNeeded()` does: sorting is
        /// linearithmic, so one-at-a-time would make a table sitting at the ceiling pay a full
        /// sort on every single insert that follows.
        ///
        /// Dropping an entry is only ever *un-caching*. If clients are still using that group,
        /// they hold their own token and the group keeps running until the last of them is done;
        /// if nobody is, releasing this reference is what retires it. Either way this call does
        /// no shutting down of its own, and never has to decide whether a group is still in use.
        ///
        /// - Warning: Lockless. The caller must be holding ``lock``.
        private func _evictIfNeeded() {
            guard _groups.count > maximumCount else {
                return
            }

            let target = max(maximumCount - (maximumCount / 4), 1)
            let excess = _groups.count - target

            let oldest =
                _groups
                .sorted { $0.value.usedAt < $1.value.usedAt }
                .prefix(excess)

            for (key, _) in oldest {
                _groups[key] = nil
            }
        }
    }
}

// MARK: - EventLoopGroupManager extension

extension Internals.EventLoopGroupManager {

    /// - Note: `usedAt` is a monotonically increasing counter rather than a timestamp. Ordering
    /// is the only thing eviction needs from it, and a counter gives that exactly, with no clock
    /// to move underneath it and no two entries able to tie.
    fileprivate struct Entry {
        let token: Internals.EventLoopGroupToken
        let usedAt: UInt64
    }
}

#endif
