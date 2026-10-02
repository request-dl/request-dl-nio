//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension Internals {

    /// Accumulates the transactions one request went through, as the transport reports them.
    ///
    /// A request that follows redirects, or resumes a download, runs several exchanges on the wire, and
    /// each one is reported by the transport when it ends, on whatever thread that transport uses. The
    /// collector is the one place those reports meet, so the task that reads them back later does not
    /// need to know which transport produced them or on which thread they arrived.
    ///
    /// Reading is a snapshot. A transaction that has not ended yet is not in it, which is why the
    /// metrics of a body that is still streaming are incomplete until it has been drained.
    package final class RequestMetricsCollector: @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _transactions: [TransactionMetrics] = []

        // MARK: - Inits

        package init() {}

        // MARK: - Internal methods

        /// Records a transaction that has ended, after the ones that came before it.
        package func append(_ transaction: TransactionMetrics) {
            lock.withLock {
                _transactions.append(transaction)
            }
        }

        /// The transactions that have ended so far, in the order they ended.
        package func transactions() -> [TransactionMetrics] {
            lock.withLock { _transactions }
        }
    }
}
