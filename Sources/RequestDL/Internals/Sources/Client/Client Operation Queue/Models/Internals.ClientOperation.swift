//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension Internals {

    /// One in flight request, from the point of view of the client that is counting them.
    final class ClientOperation: @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()

        private weak var delegate: QueueClientOperationDelegate?

        // MARK: - Unsafe properties

        private var _isCompleted = false

        // MARK: - Init

        init(delegate: QueueClientOperationDelegate?) {
            self.delegate = delegate
        }

        deinit {
            // An operation dropped without completing would leave its client counted as busy
            // forever, so it would never be recycled and would hold its connections open.
            complete()
        }

        // MARK: - Internal methods

        /// Idempotent. Cancellation, normal completion and deallocation can all reach this, and
        /// only the first of them counts.
        func complete() {
            let shouldReport = lock.withLock { () -> Bool in
                guard !_isCompleted else {
                    return false
                }

                _isCompleted = true
                return true
            }

            guard shouldReport else {
                return
            }

            // Outside the critical section. The delegate takes the queue's lock, and keeping
            // this one held across that is how lock orders get inverted.
            delegate?.operationDidComplete(self)
        }
    }
}
