//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

extension Internals {

    /// A byte-counted credit window between a response body's producer and whoever ends up
    /// reading it, so the producer can be told to stop instead of buffering without bound.
    ///
    /// Exists because nothing else in the pipeline can say "stop". `ReplaySubject`, behind every
    /// `Internals.AsyncStream`, is synchronous on the producing side by design: its own
    /// `SubjectBufferingPolicy` doc spells out that back pressure there "can only be applied by
    /// discarding", and discarding a response body is not an option. `.untilFirstIteration`
    /// bounds nothing either: it only stops retaining chunks the reader has already been handed.
    /// So this sits *beside* the stream rather than inside it: the stream charges it as chunks go
    /// in (see `Internals.AsyncStream.init(bufferingPolicy:flowControl:)`), its reader credits it
    /// as chunks come out, and the producer asks it whether to keep going.
    ///
    /// Counts bytes rather than chunks. Chunk sizes vary by orders of magnitude along the way
    /// (whatever NIO happened to read, then whatever `Internals.DownloadStep.ReadingMode` re-slices
    /// that into, then whatever a decoder emits), so a chunk count would bound nothing in
    /// particular.
    ///
    /// ## Liveness
    ///
    /// The producer is only ever told to wait while `bufferedBytes` is above `highWatermark`, and
    /// only resumed once readers bring it back down to `lowWatermark`. That can only deadlock if
    /// some counted byte could never reach a reader without the producer first producing more,
    /// so every charge must be for bytes a reader can actually drain on its own. This is why
    /// `Internals.DownloadBuffer` credits bytes back as soon as they move into its re-chunking
    /// accumulator: a `.length(n)` with `n` above the window, or a `.separator` line longer than
    /// it, would otherwise wait forever for input that the pause itself is withholding.
    ///
    /// Everything else that ends the exchange -- the request failing or being cancelled, or the
    /// reader going away -- calls ``release()``, which is terminal: every waiter resumes, and
    /// nothing waits again. See `Internals.ClientResponseReceiver` and
    /// `Internals.Client.execute(request:url:readingMode:uploadingBytes:decompression:cache:logger:)`
    /// for which event maps to which call on the `.nio` path, and
    /// `Internals.URLSessionClient.executeSessionTask` on the `.urlSession` one.
    ///
    /// ## Suspension
    ///
    /// ``suspend()`` shuts the window deliberately, regardless of how much is buffered, until
    /// ``resume()``: the incidental pause above, generalized to one the application asked for and
    /// that may last arbitrarily long. See `Internals.TransferControl`, which is what suspends and
    /// resumes windows as a unit.
    ///
    /// That is not a hole in the liveness argument, and the reason matters for anything built on
    /// top: a suspended window withholds input the reader may well be waiting for -- that is the
    /// point -- but the wait is never *unbounded by construction*. It ends when the application
    /// resumes, or when the exchange ends for any other reason, because ``release()`` overrides a
    /// suspension exactly like it overrides a full window. So every path that already releases
    /// the window (cancellation, the response being dropped, the reader going away, the exchange
    /// failing or finishing) also frees a producer parked by a suspension, and a producer can
    /// never be left waiting for a ``resume()`` nobody will ever call.
    ///
    /// Suspension only stops the producer. Bytes already counted keep flowing to the reader,
    /// and crediting them never wakes the producer while suspended.
    package final class FlowControlWindow: @unchecked Sendable {

        // MARK: - Internal static properties

        /// Generous on purpose. A body up to this size behaves exactly as it did before this
        /// window existed, fully buffered ahead of its reader, so only genuinely large or
        /// genuinely slow-to-read responses ever see the pause.
        package static let defaultHighWatermark = 1_048_576

        /// Half of ``defaultHighWatermark``. Resuming at the same threshold that pauses would flip
        /// the producer back and forth once per chunk; resuming lower lets it run for a while
        /// before it has to stop again, while the reader still has the remaining half to chew on.
        package static let defaultLowWatermark = 524_288

        // MARK: - Internal properties

        package let highWatermark: Int
        package let lowWatermark: Int

        /// Whether the producer may keep going right now, without waiting.
        package var isWritable: Bool {
            lock.withLock { _isWritable }
        }

        /// Whether ``suspend()`` is in effect. Stays `true` after ``release()`` if it was, even
        /// though a released window no longer holds anything back.
        package var isSuspended: Bool {
            lock.withLock { _isSuspended }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        // Every credit is for bytes an earlier charge already counted (a stream charges before it
        // sends, `Internals.DownloadBuffer` charges before it enqueues), so this never goes
        // negative. It can briefly *over*count by one part, while `Internals.DownloadBuffer` has
        // charged what it emitted but not yet credited what it dequeued; that only ever pauses a
        // producer a part early, never late, and never for good.
        private var _bufferedBytes = 0
        private var _peakBufferedBytes = 0
        private var _isReleased = false
        private var _isSuspended = false
        private var _waiters: [@Sendable () -> Void] = []

        private var _isWritable: Bool {
            _isReleased || (!_isSuspended && _bufferedBytes <= highWatermark)
        }

        // MARK: - Inits

        package init(
            highWatermark: Int = FlowControlWindow.defaultHighWatermark,
            lowWatermark: Int = FlowControlWindow.defaultLowWatermark
        ) {
            precondition(highWatermark > .zero, "A flow control window needs room for at least one byte")
            precondition(
                (0...highWatermark).contains(lowWatermark),
                "A flow control window resumes at or below the point where it pauses"
            )

            self.highWatermark = highWatermark
            self.lowWatermark = lowWatermark
        }

        deinit {
            // Safety net, the same one `AsyncSignal` keeps: nothing can credit this window anymore,
            // so whoever is still waiting is released rather than left suspended. For the NIO
            // producer that is also what keeps its `EventLoopPromise` from being dropped
            // unfulfilled, which NIO traps on in debug builds.
            for waiter in _waiters {
                waiter()
            }
        }

        // MARK: - Internal methods

        /// Counts `bytes` as buffered ahead of the reader.
        package func charge(_ bytes: Int) {
            guard bytes != .zero else {
                return
            }

            lock.withLock {
                _bufferedBytes += bytes
                _peakBufferedBytes = max(_peakBufferedBytes, _bufferedBytes)
            }
        }

        /// Stops counting `bytes`, resuming a waiting producer once the backlog is down to
        /// ``lowWatermark``.
        package func credit(_ bytes: Int) {
            guard bytes != .zero else {
                return
            }

            let waiters = lock.withLock { () -> [@Sendable () -> Void] in
                _bufferedBytes -= bytes

                // A suspended window stays shut however far the reader drains it; `resume()`
                // decides then whether the backlog is small enough to let the producer go.
                guard !_isSuspended, _bufferedBytes <= lowWatermark else {
                    return []
                }

                return _drainWaiters()
            }

            // Outside the critical section: these resume a continuation or fulfil a promise.
            for waiter in waiters {
                waiter()
            }
        }

        /// Runs `body` once the producer may continue: right away when ``isWritable``, or once
        /// readers have drained the backlog to ``lowWatermark``, or once ``release()`` is called,
        /// whichever comes first. Always runs exactly once.
        package func whenWritable(_ body: @escaping @Sendable () -> Void) {
            // Decided under the same lock `credit` drains waiters under, so a reader catching up
            // between the producer's own `isWritable` check and this call cannot be missed: the
            // waiter is either registered before that credit runs, or sees its effect here.
            let runsNow = lock.withLock { () -> Bool in
                guard !_isWritable else {
                    return true
                }

                _waiters.append(body)
                return false
            }

            if runsNow {
                body()
            }
        }

        /// Suspends until the producer may continue, under the same rule as
        /// ``whenWritable(_:)``.
        ///
        /// - Important: Not cancellable on its own. Whoever waits here decides what cancelling
        /// means for the window (for a producer that owns it outright, typically ``release()``),
        /// and does that from its own `withTaskCancellationHandler`.
        package func waitUntilWritable() async {
            await withCheckedContinuation { continuation in
                whenWritable {
                    continuation.resume()
                }
            }
        }

        /// Shuts the window regardless of the backlog, until ``resume()`` (or ``release()``).
        ///
        /// Takes effect the next time the producer checks ``isWritable`` or registers a waiter:
        /// a producer never gets interrupted mid-chunk, so whatever it is producing right now
        /// still goes through. Idempotent; a no-op on a released window.
        package func suspend() {
            lock.withLock {
                _isSuspended = true
            }
        }

        /// Lifts ``suspend()``. A waiting producer resumes right away if the backlog is within
        /// ``highWatermark`` -- the same test a producer that had not been suspended would have
        /// passed -- and otherwise once readers drain it to ``lowWatermark``, as usual.
        /// Idempotent.
        package func resume() {
            let waiters = lock.withLock { () -> [@Sendable () -> Void] in
                _isSuspended = false

                guard _isWritable else {
                    return []
                }

                return _drainWaiters()
            }

            for waiter in waiters {
                waiter()
            }
        }

        /// Opens the window for good: every waiting producer resumes, and none ever waits again.
        ///
        /// Terminal and idempotent. Called once the exchange cannot make progress through
        /// reading anymore -- it failed, was cancelled, finished, or lost its reader -- so pausing
        /// could only turn into a hang from here on.
        package func release() {
            let waiters = lock.withLock { () -> [@Sendable () -> Void] in
                _isReleased = true
                return _drainWaiters()
            }

            for waiter in waiters {
                waiter()
            }
        }

        // MARK: - Unsafe methods

        private func _drainWaiters() -> [@Sendable () -> Void] {
            let waiters = _waiters
            _waiters = []
            return waiters
        }
    }
}

// MARK: - Testing

@_spi(Testing)
extension Internals.FlowControlWindow {

    /// Bytes currently counted as buffered ahead of the reader.
    public var bufferedBytesForTesting: Int {
        lock.withLock { _bufferedBytes }
    }

    /// The most bytes ever counted as buffered at once, which is what a test asserting a bound
    /// on memory actually needs: the current value alone says nothing about how high it got.
    public var peakBufferedBytesForTesting: Int {
        lock.withLock { _peakBufferedBytes }
    }

    /// Producers currently waiting for the window to open.
    public var waitingCountForTesting: Int {
        lock.withLock { _waiters.count }
    }

    public var isReleasedForTesting: Bool {
        lock.withLock { _isReleased }
    }
}
