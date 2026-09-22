//
// See LICENSE for this package's licensing information.
//

// Only used by Internals.ClientManager+NIO.swift, itself NIO-only.
#if canImport(NIOCore)

import NIOCore
import SwiftAsyncStream

extension Internals {

    package final class EventLoopGroupManager: @unchecked Sendable {

        // MARK: - Internal static properties

        package static let shared = EventLoopGroupManager()

        /// A ceiling on how many event-loop groups may be tracked at once.
        ///
        /// Same shape and same reason as `Internals.Storage.maximumCount`: a ceiling, not a
        /// working limit, so that a workload producing a great many distinct session identifiers
        /// cannot grow the table without bound. It is set far below `Storage`'s, because an entry
        /// here is a whole set of OS threads rather than a single cached value — `Session(_:
        /// numberOfThreads:)` with a fresh identifier per request otherwise leaks a
        /// `MultiThreadedEventLoopGroup`, threads and all, for the life of the process.
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

        /// How many groups are currently tracked. Bookkeeping only; nothing in the resolution
        /// path reads it.
        package var count: Int {
            get async {
                await lock.withLock { _groups.count }
            }
        }

        // MARK: - Private properties

        private let lock = AsyncLock(watchdog: watchdog)
        private let maximumCount: Int

        /// The shutdowns started by eviction but not yet finished.
        ///
        /// They run detached, off the evicting caller's path, so without something to join them
        /// "this group has been retired" would only ever be observable by racing the group's own
        /// API. `PendingTasks` is the package's `AsyncSignal`-backed way to wait on exactly that,
        /// already used for cache writes.
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
        ) async -> EventLoopGroup {
            let (group, evicted) = await lock.withLock { () -> (EventLoopGroup, [EventLoopGroup]) in
                let sessionProviderID = sessionProvider.uniqueIdentifier(with: options)

                _sequence &+= 1

                if let existing = _groups[sessionProviderID] {
                    // Reinserting refreshes the entry's position in the eviction order, so a
                    // group that keeps being asked for keeps moving away from the front of it.
                    _groups[sessionProviderID] = Entry(
                        group: existing.group,
                        isOwned: existing.isOwned,
                        usedAt: _sequence
                    )
                    return (existing.group, [])
                }

                let group = sessionProvider.group(with: options)

                _groups[sessionProviderID] = Entry(
                    group: group,
                    isOwned: sessionProvider.createsGroup,
                    usedAt: _sequence
                )

                return (group, _evictIfNeeded())
            }

            shutdownDetached(evicted)

            return group
        }

        /// Suspends until every shutdown this manager has started has finished.
        ///
        /// Eviction hands its groups off to a detached drain, so without this "the group is gone"
        /// is only observable by poking at the group itself and hoping the timing works out.
        package func waitUntilShutdownsComplete() async {
            await shutdowns.waitUntilIdle()
        }

        // MARK: - Private methods

        /// Drains `groups` off the caller's own path.
        ///
        /// An eviction is bookkeeping the caller never asked for — it is in the middle of being
        /// handed a brand-new group — so it should not wait on a shutdown, and `lock` must not be
        /// held across one either. Same reasoning as
        /// `Internals.ClientManager.shutdownDetached(_:)`, with `shutdowns` added so the drain is
        /// joinable rather than merely fire-and-forget.
        private func shutdownDetached(_ groups: [EventLoopGroup]) {
            for group in groups {
                shutdowns.run { try? await group.shutdownGracefully() }
            }
        }

        // MARK: - Unsafe methods

        /// Brings `_groups` back under ``maximumCount``, least recently asked for first, and
        /// hands back the groups this manager built itself so the caller can shut them down.
        ///
        /// Drops to three quarters of the ceiling in one pass rather than evicting one entry per
        /// insert, for the same reason `Internals.Storage._evictIfNeeded()` does: sorting is
        /// linearithmic, so one-at-a-time would make a table sitting at the ceiling pay a full
        /// sort on every single insert that follows.
        ///
        /// A borrowed group (NIO's shared singletons, a caller's own) is dropped from the table
        /// but never shut down — see `SessionProvider.createsGroup`. It is re-obtained, unchanged,
        /// the next time its provider is resolved.
        ///
        /// - Warning: Lockless. The caller must be holding ``lock``.
        private func _evictIfNeeded() -> [EventLoopGroup] {
            guard _groups.count > maximumCount else {
                return []
            }

            let target = max(maximumCount - (maximumCount / 4), 1)
            let excess = _groups.count - target

            let oldest =
                _groups
                .sorted { $0.value.usedAt < $1.value.usedAt }
                .prefix(excess)

            var shutdownCandidates = [EventLoopGroup]()

            for (key, entry) in oldest {
                _groups[key] = nil

                if entry.isOwned {
                    shutdownCandidates.append(entry.group)
                }
            }

            return shutdownCandidates
        }
    }
}

// MARK: - EventLoopGroupManager extension

extension Internals.EventLoopGroupManager {

    /// - Note: `usedAt` is a monotonically increasing counter rather than a timestamp. Ordering
    /// is the only thing eviction needs from it, and a counter gives that exactly, with no clock
    /// to move underneath it and no two entries able to tie.
    fileprivate struct Entry {
        let group: EventLoopGroup
        let isOwned: Bool
        let usedAt: UInt64
    }
}

#endif
