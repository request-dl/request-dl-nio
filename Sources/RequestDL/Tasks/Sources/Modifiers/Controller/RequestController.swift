//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import SwiftAsyncStream

/// Suspends and resumes the requests it is attached to (see ``RequestTask/controller(_:)``),
/// without cancelling them.
///
/// ```swift
/// let controller = RequestController()
///
/// let task = DownloadTask { ... }
///     .controller(controller)
///
/// // Later, from anywhere:
/// controller.suspend()
/// controller.resume()
/// ```
///
/// A controller is a shared switch, not a handle on one request: it can be attached to any number
/// of executions, for instance every request of a ``GroupTask``, and ``suspend()`` pauses all of
/// them at once. Its state is sticky: a request that starts while the controller is suspended
/// starts suspended, so there is no window between creating a task and pausing it.
///
/// ## What a suspension does
///
/// It stops the *network*, not the reader. Bytes already buffered ahead of the response's reader
/// keep reaching it, so progress can advance a little after ``suspend()`` (about half a MiB on the
/// `.nio` executor, a few MiB on `.urlSession`, whose CFNetwork reads ahead). The connection stays
/// open, which means it is subject to whatever idle timeouts apply while nothing moves: the
/// client's own, the server's and any middlebox's. A suspension that outlives the connection ends
/// the request like any other dropped connection would, promptly and never by hanging. A suspended
/// `.urlSession` upload fails with `URLError.timedOut` once its idle timeout passes.
///
/// ## Cancellation
///
/// The controller does not cancel anything. Cancel the `Task` running the request as usual; that
/// also ends a suspension.
///
/// - Note: It has no effect on ``BackgroundDownloadTask``, which the operating system runs.
public final class RequestController: @unchecked Sendable {

    private struct Attachment {
        weak var control: Internals.TransferControl?
    }

    // MARK: - Private properties

    private let lock = Lock()

    // MARK: - Unsafe properties

    private var _isSuspended = false
    private var _attachments: [Attachment] = []

    // MARK: - Inits

    /// Creates a controller in the resumed state, attached to nothing.
    public init() {}

    // MARK: - Public properties

    /// Whether the controller is currently suspended.
    public var isSuspended: Bool {
        lock.withLock { _isSuspended }
    }

    // MARK: - Public methods

    /// Stops every request attached to this controller at its next step, until ``resume()``.
    ///
    /// Synchronous and idempotent. Requests that start while suspended start suspended.
    public func suspend() {
        // Applied under the lock, so a `suspend()` and a `resume()` racing each other leave every
        // attached request in the state of whichever ran last, never a mix of both.
        lock.withLock {
            _isSuspended = true
            _attachments.removeAll { $0.control == nil }

            for attachment in _attachments {
                attachment.control?.suspend()
            }
        }
    }

    /// Lets every request attached to this controller continue. Synchronous and idempotent.
    public func resume() {
        lock.withLock {
            _isSuspended = false
            _attachments.removeAll { $0.control == nil }

            for attachment in _attachments {
                attachment.control?.resume()
            }
        }
    }

    // MARK: - Internal methods

    /// Makes `control`, one execution's, follow this controller, starting with its current state.
    ///
    /// Held weakly: an execution owns its own control for as long as it runs, and once it is over
    /// there is nothing left to suspend.
    func attach(_ control: Internals.TransferControl) {
        lock.withLock {
            _attachments.removeAll { $0.control == nil }
            _attachments.append(Attachment(control: control))

            if _isSuspended {
                control.suspend()
            }
        }
    }
}
