//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension Internals {

    /// Suspends and resumes one request execution in flight, in both directions, on whichever
    /// executor it runs: the internal mechanism behind the public `RequestController`.
    ///
    /// Nothing here is OS-specific. Every executor already moves bytes through a producer that
    /// RequestDL itself drives, and each producer waits on an `Internals.FlowControlWindow` whenever
    /// that window is shut; a suspension simply shuts every window of the execution at once:
    ///
    /// - The response body's window, which each executor ``attach(_:)``es. Its producer is the
    ///   `.nio` `HTTPClientResponseDelegate` (AsyncHTTPClient reads nothing more off the socket
    ///   while a body part's future is pending) or the `.urlSession` pump (CFNetwork reads nothing
    ///   more once its own read-ahead behind `URLSession.AsyncBytes` is full).
    /// - ``gate``, a window nothing is ever charged against, so it is shut exactly while
    ///   suspended. The request body's producer waits on it between chunks
    ///   (`Internals.StreamWriterSequence` on `.nio`, `Internals.URLSessionUploadBodyPump` on
    ///   `.urlSession`), and so does a download reconnection (see ``resumption``), which has no
    ///   business opening a new connection while the application asked for the transfer to stay
    ///   paused.
    ///
    /// ## What a suspension does and doesn't do
    ///
    /// It stops the *network*, within one producer step: at most a chunk of the request body, or
    /// a body part (`.nio`) / CFNetwork's read-ahead (`.urlSession`) of the response. Bytes already
    /// buffered ahead of the response's reader keep reaching it. The connection itself stays
    /// open, which means it is exposed to whatever idle timeouts apply while nothing moves: the
    /// client's own (`timeoutIntervalForRequest` on `.urlSession`, for either direction; the
    /// configured read timeout on `.nio`, for a download only), the server's, and any middlebox's.
    /// A suspension outliving the connection therefore ends the exchange like any other dropped
    /// connection does, promptly and never by hanging, unless ``resumption`` can reconnect a
    /// download.
    ///
    /// ## Liveness
    ///
    /// A suspended producer waits for ``resume()`` *or* for its window's `release()`, which every
    /// terminal path already calls (see `Internals.FlowControlWindow`'s own "Suspension" section),
    /// so no suspension can outlive the exchange it belongs to. ``release()`` does the same for
    /// ``gate``, and each executor calls it once the exchange has ended for good.
    ///
    /// One instance per request execution: it attaches that execution's windows and is released
    /// with it.
    package final class TransferControl: @unchecked Sendable {

        // MARK: - Internal properties

        /// Reconnects a download whose connection is lost mid-body with an HTTP `Range` request,
        /// when the response allows it (see `Internals.RangeResumptionPlan`). `nil` keeps the
        /// behaviour of an execution without a `TransferControl`: a lost connection fails the body.
        package let resumption: Internals.DownloadResumptionPolicy?

        /// Whether anything can suspend this execution. `false` for an execution that only asked
        /// to reconnect a lost download (see ``resumption``): it then has no use for the request
        /// body producers waiting on ``gate``, and must not change how a request body is sent.
        package let allowsSuspension: Bool

        /// Told about this execution as it happens on the network, when something observes it.
        ///
        /// Lives here because this is the one object every executor already receives for an
        /// execution and every one of its ends (suspension, reconnection, the exchange itself)
        /// can reach.
        package let observer: Internals.ExecutionObserver?

        /// Where the download starts, when it continues one a previous launch left unfinished (see
        /// `Internals.DownloadResumptionStart`). Only meaningful together with ``resumption``.
        package let resumptionStart: Internals.DownloadResumptionStart?

        /// Shut exactly while suspended (and open for good once released). What request-body
        /// producers and download reconnections wait on.
        package let gate = Internals.FlowControlWindow()

        /// ``gate``, for the request body producers to wait on: `nil` when nothing can suspend
        /// this execution, so the body is sent exactly as it is without a control at all.
        package var uploadGate: Internals.FlowControlWindow? {
            allowsSuspension ? gate : nil
        }

        package var isSuspended: Bool {
            lock.withLock { _isSuspended }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _isSuspended = false
        private var _windows: [Internals.FlowControlWindow] = []
        private var _followers: [TransferControl] = []

        // MARK: - Inits

        package init(
            resumption: Internals.DownloadResumptionPolicy? = nil,
            allowsSuspension: Bool = true,
            observer: Internals.ExecutionObserver? = nil,
            resumptionStart: Internals.DownloadResumptionStart? = nil
        ) {
            self.resumption = resumption
            self.allowsSuspension = allowsSuspension
            self.observer = observer
            self.resumptionStart = resumptionStart
        }

        // MARK: - Internal methods

        /// Makes `window` follow this execution's suspension, starting with its current state.
        package func attach(_ window: Internals.FlowControlWindow) {
            lock.withLock {
                _windows.append(window)

                if _isSuspended {
                    window.suspend()
                }
            }
        }

        /// Makes `follower`, the control of one exchange of this execution, follow this one's
        /// suspension, starting with its current state.
        ///
        /// For an execution that is more than one exchange (a resumable upload creates the upload,
        /// then sends its body, then asks where the server is, then sends the rest): each exchange
        /// has a control of its own, which its executor releases once that exchange is over, while
        /// this one is what a `RequestController` holds and is released only with the execution.
        package func attach(_ follower: TransferControl) {
            lock.withLock {
                _followers.append(follower)

                if _isSuspended {
                    follower.suspend()
                }
            }
        }

        /// Stops following `follower`, whose exchange is over.
        package func detach(_ follower: TransferControl) {
            lock.withLock {
                _followers.removeAll { $0 === follower }
            }
        }

        /// Stops every producer of this execution at its next step, until ``resume()``.
        ///
        /// Idempotent. Recorded even once the exchange is over, where it no longer has anything
        /// to hold back.
        package func suspend() {
            // Applied under the lock, so a `suspend()` and a `resume()` racing each other leave
            // every window in the state of whichever ran last, never a mix of both. Nothing a
            // window runs from here (a continuation or a promise being resumed) calls back into
            // this type, which is what makes holding the lock across it safe.
            lock.withLock {
                _isSuspended = true
                gate.suspend()

                for window in _windows {
                    window.suspend()
                }

                for follower in _followers {
                    follower.suspend()
                }

                // Only recorded here: the observer delivers from a task of its own, so nothing of
                // an observer's runs under this lock.
                observer?.didChange(.suspended)
            }
        }

        /// Lets every producer of this execution continue. Idempotent.
        package func resume() {
            lock.withLock {
                _isSuspended = false
                gate.resume()

                for window in _windows {
                    window.resume()
                }

                for follower in _followers {
                    follower.resume()
                }

                observer?.didChange(.resumed)
            }
        }

        /// Suspends until not suspended (or released). Not cancellable on its own; see
        /// `Internals.FlowControlWindow.waitUntilWritable()`.
        package func waitUntilResumed() async {
            await gate.waitUntilWritable()
        }

        /// Opens ``gate`` for good, freeing anything still waiting on it. Called by each executor
        /// once the exchange has ended, whichever way. The attached windows are released by
        /// their own terminal paths, not here.
        ///
        /// Deliberately doesn't take `lock`: it's called from those terminal paths, some of
        /// which can run from inside a ``resume()`` (a window resuming a `.nio` body part inline
        /// on its event loop, and the exchange finishing right there).
        package func release() {
            gate.release()
        }
    }
}
