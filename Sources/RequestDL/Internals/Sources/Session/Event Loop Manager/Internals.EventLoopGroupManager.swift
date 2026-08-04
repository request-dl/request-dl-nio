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
        /// - Important: Must not hop through `Task.detached(priority: .background)`.
        /// `Task.detached` does not inherit priority, so if the caller awaits the result, a
        /// `.userInitiated` request ends up waiting on a `.background` task: a textbook priority
        /// inversion, right on the path that has to run before any request goes out. Background
        /// is also the first thing the system defers under thermal pressure or Low Power Mode,
        /// which is exactly when a request should not be stalling.
        ///
        /// If a future change needs that hop to work around something, that something needs a
        /// different answer.
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
