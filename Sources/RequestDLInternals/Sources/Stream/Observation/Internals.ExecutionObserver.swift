//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension Internals {

    /// What happened to one request execution on the network, aggregated and handed to whoever
    /// observes it (the public `RequestMonitor`).
    ///
    /// Fed by whichever executor runs the request, at the places where bytes actually cross the
    /// transport, so what it counts is what moved on the network and not what a reader has
    /// consumed since. Never runs observer code on the caller's thread: the executors call these
    /// methods from the NIO event loop, CFNetwork's queues and the receivers' locks, none of which
    /// may wait on arbitrary code. Everything is recorded under a lock and delivered from a
    /// separate task, in order.
    ///
    /// ## Progress is coalesced, on purpose
    ///
    /// A run of byte counts that hasn't been delivered yet is merged into one, its `total` being
    /// the latest and its delta the sum. So an observer slower than the network sees fewer, larger
    /// steps instead of the backlog growing without bound, which for a large download would be
    /// unbounded memory held by a mere progress callback. Lifecycle events are never merged or
    /// dropped, and stay ordered against the progress around them.
    ///
    /// ## After the end
    ///
    /// The first ``State/finished`` or ``State/failed(_:)`` closes the observer: whatever an
    /// executor reports afterwards (a late suspension, a duplicate ending) is ignored, so callers
    /// may report an ending from every path that can produce one.
    package final class ExecutionObserver: @unchecked Sendable {

        // MARK: - Inner types

        package enum State: Sendable {
            case started
            case suspended
            case resumed
            /// A lost download connection is being continued, for the `attempt`th time in all.
            case reconnecting(attempt: Int)
            case finished
            case failed(any Error)

            fileprivate var isTerminal: Bool {
                switch self {
                case .finished, .failed:
                    return true
                default:
                    return false
                }
            }
        }

        /// One direction's progress since the previous delivery.
        package struct Transfer: Sendable, Hashable {
            /// Bytes since the previous delivery.
            package let bytes: Int
            /// Bytes since the request started.
            package let total: Int
            /// What `total` is expected to reach, when known.
            package let expected: Int?
        }

        package enum Event: Sendable {
            case progress(upload: Transfer?, download: Transfer?)
            case state(State)
            /// The head of the response came in: its status code.
            case head(statusCode: Int)
            /// A transaction the transport has finished measuring.
            case metrics(TransactionMetrics)
        }

        // MARK: - Private properties

        private let lock = Lock()
        private let deliver: @Sendable (Event) async -> Void

        // MARK: - Unsafe properties

        private var _uploadTotal = 0
        private var _downloadTotal = 0
        private var _uploadPending = 0
        private var _downloadPending = 0
        private var _expectedUpload: Int?
        private var _expectedDownload: Int?
        private var _entries: [Event] = []
        private var _isDelivering = false
        private var _isClosed = false
        private var _isSuspended = false

        // MARK: - Inits

        /// - Parameter deliver: Called for one event at a time, in order, from a task of its own.
        package init(deliver: @escaping @Sendable (Event) async -> Void) {
            self.deliver = deliver
        }

        // MARK: - Internal methods

        /// What the request body is expected to add up to, when it is known up front.
        package func expectUpload(_ bytes: Int?) {
            lock.withLock { _expectedUpload = bytes }
        }

        /// `bytes` of the request body went out on the transport.
        package func didSend(_ bytes: Int) {
            guard bytes > .zero else {
                return
            }

            schedule {
                _uploadTotal += bytes
                _uploadPending += bytes
            }
        }

        /// `bytes` of the response body came in off the transport.
        package func didReceive(_ bytes: Int) {
            guard bytes > .zero else {
                return
            }

            schedule {
                _downloadTotal += bytes
                _downloadPending += bytes
            }
        }

        /// What the response body is expected to add up to, from its head.
        ///
        /// Known only when the head says so in a way that holds for the bytes counted: a
        /// `Content-Length`, and no content coding, which a transport may already have decoded
        /// by the time the bytes are counted.
        package func didReceiveHead(_ head: Internals.ResponseHead) {
            let isEncoded =
                head
                .headerValues(named: "Content-Encoding")
                .flatMap { $0.split(separator: ",") }
                .map { $0.trimming(where: \.isWhitespace).lowercased() }
                .contains { !$0.isEmpty && $0 != "identity" }

            let lengths = Set(
                head
                    .headerValues(named: "Content-Length")
                    .flatMap { $0.split(separator: ",") }
                    .map { $0.trimming(where: \.isWhitespace) }
            )

            // Conflicting lengths mean it isn't known, not that any of them is.
            let length = lengths.count == 1 ? lengths.first.flatMap { Int($0) } : nil

            let shouldStart = lock.withLock { () -> Bool in
                guard !_isClosed else {
                    return false
                }

                // Every head is told, in order with the rest: the last one is the response.
                flushProgress()
                _entries.append(.head(statusCode: Int(head.status.code)))

                if _expectedDownload == nil {
                    _expectedDownload = isEncoded ? nil : length
                }

                return startDelivering()
            }

            if shouldStart {
                spawn()
            }
        }

        package func didChange(_ state: State) {
            let isSuspension: Bool?

            switch state {
            case .suspended:
                isSuspension = true
            case .resumed:
                isSuspension = false
            default:
                isSuspension = nil
            }

            let shouldStart = lock.withLock { () -> Bool in
                guard !_isClosed else {
                    return false
                }

                // A repeated suspend or resume isn't a change.
                if let isSuspension {
                    guard _isSuspended != isSuspension else {
                        return false
                    }

                    _isSuspended = isSuspension
                }

                // Progress recorded so far goes ahead of this event, so the two stay in the
                // order they happened.
                flushProgress()
                _entries.append(.state(state))

                if state.isTerminal {
                    _isClosed = true
                }

                return startDelivering()
            }

            if shouldStart {
                spawn()
            }
        }

        /// A transaction of this execution was measured.
        ///
        /// Unlike everything else, this is still delivered once the observer is closed: a transport
        /// reports what it measured when it is done with the transaction, which for `URLSession` is
        /// after the response body has ended, and so after the ending this observer closed on. It
        /// goes after whatever is already queued, so it never overtakes the ending it follows.
        package func didCollect(_ transaction: TransactionMetrics) {
            let shouldStart = lock.withLock { () -> Bool in
                flushProgress()
                _entries.append(.metrics(transaction))
                return startDelivering()
            }

            if shouldStart {
                spawn()
            }
        }

        // MARK: - Private methods

        private func schedule(_ update: () -> Void) {
            let shouldStart = lock.withLock { () -> Bool in
                guard !_isClosed else {
                    return false
                }

                update()
                return startDelivering()
            }

            if shouldStart {
                spawn()
            }
        }

        /// Turns what was counted since the last event into one, in place at the end of the queue.
        private func flushProgress() {
            guard _uploadPending > .zero || _downloadPending > .zero else {
                return
            }

            _entries.append(
                .progress(
                    upload: _uploadPending > .zero
                        ? Transfer(bytes: _uploadPending, total: _uploadTotal, expected: _expectedUpload)
                        : nil,
                    download: _downloadPending > .zero
                        ? Transfer(bytes: _downloadPending, total: _downloadTotal, expected: _expectedDownload)
                        : nil
                )
            )

            _uploadPending = .zero
            _downloadPending = .zero
        }

        /// - Returns: Whether the caller has to start the delivery task: `false` when one is
        ///   already running and will find the new work.
        private func startDelivering() -> Bool {
            guard !_isDelivering else {
                return false
            }

            _isDelivering = true
            return true
        }

        private func spawn() {
            Task.detached { [self] in
                while let event = next() {
                    await deliver(event)
                }
            }
        }

        /// The next event to deliver, or `nil` once there is nothing left, which also ends the
        /// current delivery task under the same lock that new work is added under.
        private func next() -> Event? {
            lock.withLock {
                if _entries.isEmpty {
                    flushProgress()
                }

                guard !_entries.isEmpty else {
                    _isDelivering = false
                    return nil
                }

                return _entries.removeFirst()
            }
        }
    }
}
