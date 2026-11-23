//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension Internals.ClientManager {

    /// What one limit of `maximumConcurrentConnections` is shared by: a session provider and the
    /// number of requests it allows. See
    /// ``Internals/ClientManager/throttledExecutor(provider:maximumConcurrentConnections:)``.
    struct ThrottleKey: Hashable, Sendable {

        let providerID: String
        let maximumConcurrentConnections: Int
    }

    /// A semaphore the table does not keep alive: whoever uses it does.
    struct WeakSemaphore {

        // MARK: - Internal properties

        weak private(set) var semaphore: AsyncCancellableSemaphore?

        // MARK: - Inits

        init(_ semaphore: AsyncCancellableSemaphore) {
            self.semaphore = semaphore
        }
    }
}
