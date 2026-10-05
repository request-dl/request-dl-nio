//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

/// Where a request execution is in its life, as reported to a ``RequestMonitor``.
///
/// Every execution goes through ``started`` first and ends with exactly one of ``finished`` or
/// ``failed(_:)``, after which nothing more is reported for it. What happens in between depends on
/// what the request was asked to do.
public enum RequestState: Sendable {

    /// The request is about to be sent.
    case started

    /// A ``RequestController`` suspended the transfer.
    case suspended

    /// A ``RequestController`` resumed the transfer.
    case resumed

    /// The connection of a download or an upload was lost and it is being continued from where it
    /// stopped (see ``RequestTask/resumingDownloads(_:)`` and
    /// ``RequestTask/resumingUploads(_:maximumAttemptsWithoutProgress:delay:onCancellation:)``).
    /// `attempt` counts the reconnections of this transfer, from 1.
    case reconnecting(attempt: Int)

    /// The request completed, and its body was received in full. A response served from the cache
    /// finishes right after it starts, having moved nothing on the network.
    case finished

    /// The request failed with `error`, or was cancelled.
    case failed(any Error)
}

// MARK: - Internal state

extension RequestState {

    init(_ state: Internals.ExecutionObserver.State) {
        switch state {
        case .started:
            self = .started
        case .suspended:
            self = .suspended
        case .resumed:
            self = .resumed
        case .reconnecting(let attempt):
            self = .reconnecting(attempt: attempt)
        case .finished:
            self = .finished
        case .failed(let error):
            self = .failed(error)
        }
    }
}
