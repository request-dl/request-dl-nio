//
// See LICENSE for this package's licensing information.
//

// AsyncHTTPClient back pressure: .nio/.nioTransportServices only.
#if canImport(NIOCore)

import NIOCore
import SwiftAsyncStream

extension Internals {

    /// The future a `.nio` response delegate returns from `didReceiveBodyPart` while its
    /// `Internals.FlowControlWindow` is shut: AsyncHTTPClient reads nothing more off the
    /// connection until it completes.
    ///
    /// It completes once the window opens, like before, but can also be completed on its own
    /// with ``complete()``: when a download is about to continue on a new exchange
    /// (`Internals.NIODownloadReconnection`), the exchange that failed must not be left with a
    /// pending future, yet the window it was waiting on is shared with the continuation and must
    /// stay exactly as it is -- releasing it, as a terminal failure does, would leave the rest of
    /// the download unmetered and deaf to a suspension.
    final class PausedBodyPart: @unchecked Sendable {

        // MARK: - Internal properties

        var futureResult: EventLoopFuture<Void> {
            promise.futureResult
        }

        // MARK: - Private properties

        private let promise: EventLoopPromise<Void>
        private let lock = Lock()

        // MARK: - Unsafe properties

        private var _isCompleted = false

        // MARK: - Inits

        private init(eventLoop: EventLoop) {
            promise = eventLoop.makePromise(of: Void.self)
        }

        // MARK: - Internal static methods

        /// A future that is already complete while `window` is writable (or absent), and
        /// otherwise a paused part that completes once it is.
        ///
        /// - Returns: The future to hand AsyncHTTPClient, and the paused part behind it, if any.
        static func gate(
            _ window: Internals.FlowControlWindow?,
            on eventLoop: EventLoop
        ) -> (EventLoopFuture<Void>, PausedBodyPart?) {
            guard let window, !window.isWritable else {
                return (eventLoop.makeSucceededVoidFuture(), nil)
            }

            let part = PausedBodyPart(eventLoop: eventLoop)

            window.whenWritable {
                part.complete()
            }

            return (part.futureResult, part)
        }

        // MARK: - Internal methods

        /// Idempotent: whichever of the window opening and an explicit completion comes first
        /// wins, and the other doesn't touch the promise again.
        func complete() {
            let isFirst = lock.withLock { () -> Bool in
                guard !_isCompleted else {
                    return false
                }

                _isCompleted = true
                return true
            }

            if isFirst {
                promise.succeed(())
            }
        }
    }
}

#endif
