//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import SwiftAsyncStream

extension Internals {

    final class EventLoopGroupManager: @unchecked Sendable {

        // MARK: - Internal static properties

        static let shared = EventLoopGroupManager()

        // MARK: - Private properties

        private let lock = AsyncLock()

        // MARK: - Unsafe properties

        @preconcurrency
        private var _groups = HashTable<String, EventLoopGroup>()

        // MARK: - Internal methods

        /// Returns the event loop group for a provider, creating it the first time.
        ///
        /// The hop through `Task.detached(priority: .background)` that used to wrap this is
        /// gone. `Task.detached` does not inherit priority, and the caller awaited its result,
        /// so a `.userInitiated` request ended up waiting on a `.background` task: a textbook
        /// priority inversion, right on the path that has to run before any request goes out.
        /// Background is also the first thing the system defers under thermal pressure or Low
        /// Power Mode, which is exactly when a request should not be stalling.
        ///
        /// - Note: If the hop was there to work around something, that something is still
        /// there and needs a different answer.
        func provider(
            _ sessionProvider: SessionProvider,
            with options: SessionProviderOptions
        ) async -> EventLoopGroup {
            await lock.withLock {
                let sessionProviderID = sessionProvider.uniqueIdentifier(with: options)
                let group = _groups[sessionProviderID] ?? sessionProvider.group(with: options)
                _groups[sessionProviderID] = group
                return group
            }
        }
    }
}
