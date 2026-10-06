//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import SwiftAsyncStream

/// Stands between one exchange of a resumable upload and the execution it is part of.
///
/// An execution is a single thing to whoever watches it (a `RequestController`, a
/// `RequestMonitor`): it starts once, is suspended and resumed, and ends once. An upload is
/// several exchanges, each with an executor that reports its own end and releases its own
/// control, so none of them can be handed the execution's control: the first to end would end
/// the execution, whichever way. Each gets a control of its own instead, which follows the
/// execution's suspension, and whose reports pass through here.
///
/// - Bytes sent are always passed on: they are on the network whatever comes of the exchange, so
///   they count, retransmitted ones included.
/// - What an exchange received is passed on only if that exchange turns out to be the response of
///   the upload (``decide(final:)``). A creation, an offset query, or a `PATCH` that is going to
///   be sent again, is not what anyone is waiting for.
/// - The same goes for how it ended: only the response of the upload ends the execution.
final class ResumableUploadExchangeRelay: @unchecked Sendable {

    // MARK: - Private types

    private enum Decision {
        case undecided
        case final
        case discarded
    }

    // MARK: - Internal properties

    /// The control the executor of the exchange is given. Gone once the exchange is over, which
    /// is what ends the cycle it makes with this relay through its observer.
    var control: Internals.TransferControl? {
        lock.withLock { _control }
    }

    // MARK: - Private properties

    private let parent: Internals.TransferControl
    private let lock = Lock()

    // MARK: - Unsafe properties

    private var _control: Internals.TransferControl?
    private var _decision = Decision.undecided
    private var _pendingDownload = 0
    private var _pendingEnd: Internals.ExecutionObserver.State?

    // MARK: - Inits

    init(parent: Internals.TransferControl) {
        self.parent = parent

        // The observer holds this relay, and nothing else does once the exchange is handed over:
        // how the exchange ended is delivered after the response has already been consumed, and a
        // relay that was gone by then would never tell the execution it finished. The cycle this
        // makes (relay, control, observer, relay) is broken when the exchange is over.
        let observer = parent.observer.map { _ in
            Internals.ExecutionObserver { [self] event in
                receive(event)
            }
        }

        let control = Internals.TransferControl(
            allowsSuspension: parent.allowsSuspension,
            observer: observer
        )

        _control = control
        parent.attach(control)
    }

    // MARK: - Internal methods

    /// This exchange is the response of the upload: what it receives and how it ends is the
    /// execution's.
    func decide(final head: Internals.ResponseHead) {
        // Everything that reaches the execution goes through here under the lock, and in this
        // order: what the exchange had received before it was decided, then whatever follows,
        // then its end. Passing the first on outside the lock would let the end overtake it.
        // Nothing the execution's observer runs ever calls back into this type.
        lock.withLock {
            _decision = .final

            parent.observer?.didReceiveHead(head)
            parent.observer?.didReceive(_pendingDownload)
            _pendingDownload = .zero

            if let end = _pendingEnd {
                _pendingEnd = nil
                finish(with: end)
            }
        }
    }

    /// This exchange is not what anyone waits for.
    func discard() {
        let control = lock.withLock { () -> Internals.TransferControl? in
            _decision = .discarded
            _pendingDownload = .zero
            _pendingEnd = nil

            defer { _control = nil }
            return _control
        }

        control.map(parent.detach)
    }

    // MARK: - Private methods

    private func receive(_ event: Internals.ExecutionObserver.Event) {
        lock.withLock {
            switch event {
            case .progress(let upload, let download):
                if let upload {
                    parent.observer?.didSend(upload.bytes)
                }

                if let download {
                    switch _decision {
                    case .undecided:
                        _pendingDownload += download.bytes
                    case .final:
                        parent.observer?.didReceive(download.bytes)
                    case .discarded:
                        break
                    }
                }

            case .state(let state):
                guard state.isEnd else {
                    // A suspension or a resumption is the execution's own to report, once.
                    return
                }

                switch _decision {
                case .undecided:
                    _pendingEnd = state
                case .final:
                    finish(with: state)
                case .discarded:
                    break
                }

            case .head:
                // The head of the response of the upload is handed on by `decide(final:)`, which is
                // what says which exchange that is.
                break

            case .metrics(let transaction):
                // Whatever this exchange turned out to be, it went over the wire, and a monitor
                // hears every transaction that did. It does not wait on the decision: it is not
                // part of how the execution ends, so it cannot overtake the end it follows.
                parent.observer?.didCollect(transaction)
            }
        }
    }

    /// - Important: With the lock held.
    private func finish(with state: Internals.ExecutionObserver.State) {
        parent.observer?.didChange(state)
        parent.release()

        if let control = _control {
            parent.detach(control)
            _control = nil
        }
    }
}

extension Internals.ExecutionObserver.State {

    /// Whether this is how an execution ends.
    fileprivate var isEnd: Bool {
        switch self {
        case .finished, .failed:
            return true
        default:
            return false
        }
    }
}
