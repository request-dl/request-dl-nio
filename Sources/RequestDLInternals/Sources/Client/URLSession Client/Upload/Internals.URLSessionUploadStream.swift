//
// See LICENSE for this package's licensing information.
//

// Phase 5f of URLSESSION_TASK.md -- bridges RequestDL's push-model upload body
// (`Internals.BodySequence`/`RequestBody`, pulled via `AsyncSequence`, itself driving
// AsyncHTTPClient's `EventLoopFuture`-per-chunk `StreamWriter` on the NIO executor) into
// `URLSession`'s pull-model streamed upload (`uploadTask(withStreamedRequest:)` +
// `URLSessionTaskDelegate.urlSession(_:task:needNewBodyStream:)`, which wants a plain
// `InputStream` that something else -- URLSession's own internals, on a thread of its choosing,
// with no `async`/await context -- reads from synchronously, at whatever pace and slice size it
// picks).
//
// Deliberately not `Internals.StreamWriterSequence` (see its own doc comment): that type is
// wired specifically to `HTTPClient.Body.StreamWriter.write(_:)`, a *push* API returning an
// `EventLoopFuture`, and has no notion of a consumer pulling arbitrary-sized slices from a
// buffer at its own pace. `Buffer` below is that bounded-buffer adapter instead -- a small
// producer/consumer queue with backpressure in both directions.

#if canImport(Darwin)

import NIOCore

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

import Dispatch
import SwiftAsyncStream

extension Internals {

    /// An `InputStream` fed by draining an `AsyncSequence` of `ByteBuffer` (in practice,
    /// `Internals.BodySequence`, or `RequestBody` itself from the `RequestDL` module -- both
    /// conform) on a background `Task`, and read from synchronously by whatever thread
    /// `URLSession` calls `read(_:maxLength:)` from.
    ///
    /// One instance is good for exactly one read-through: `needNewBodyStream` can be called more
    /// than once for the same logical request (a redirect, an authentication retry), and each
    /// call needs a *fresh* stream starting from the beginning of the body again -- callers
    /// should construct a new `URLSessionUploadStream` per `needNewBodyStream` invocation rather
    /// than trying to reuse or rewind one.
    package final class URLSessionUploadStream: InputStream, @unchecked Sendable {

        // MARK: - Private properties

        private let buffer: Buffer
        private let producerTask: Task<Void, Never>

        private let stateLock = Lock()
        private var _streamStatus: Stream.Status = .notOpen
        private var _streamError: Error?
        private var _delegate: StreamDelegate?

        // MARK: - Inits

        /// - Parameters:
        ///   - body: Drained on its own detached `Task`, independent of whichever thread ends up
        ///   calling `read(_:maxLength:)` -- generic rather than typed as
        ///   `Internals.BodySequence` specifically so `RequestBody` (a `RequestDLInternals`
        ///   consumer, not a dependency of it) can be passed directly too, without this module
        ///   needing to depend on `RequestDL`.
        ///   - highWaterMark: Bytes buffered ahead of what `read` has drained before the producer
        ///   suspends. Defaults to `Internals.BodySequence`'s own maximum chunk size, so a single
        ///   produced chunk never has to wait mid-flight for room.
        package init<Body: AsyncSequence & Sendable>(
            body: Body,
            highWaterMark: Int = 1_024 * 1_024
        ) where Body.Element == ByteBuffer {
            let buffer = Buffer(highWaterMark: highWaterMark)
            self.buffer = buffer
            self.producerTask = Task.detached {
                do {
                    for try await chunk in body {
                        guard !Task.isCancelled else { break }
                        await buffer.push(Data(chunk.readableBytesView))
                    }
                    buffer.finish()
                } catch {
                    buffer.finish(error)
                }
            }
            super.init(data: Data())
        }

        deinit {
            producerTask.cancel()
            buffer.cancel()
        }

        // MARK: - Stream overrides

        // `Stream`'s own contract is "a stream is its own delegate by default," but nothing
        // here relies on `StreamDelegate`/run loop scheduling at all -- `URLSession` reads a
        // `needNewBodyStream`-provided stream by calling `read(_:maxLength:)` directly rather
        // than through `NSStreamEvent` callbacks, so `schedule(in:forMode:)`/
        // `remove(from:forMode:)` below are deliberately no-ops rather than real run loop
        // bookkeeping this stream never needs.
        package override var delegate: StreamDelegate? {
            get { stateLock.withLock { _delegate } }
            set { stateLock.withLock { _delegate = newValue } }
        }

        package override var streamStatus: Stream.Status {
            stateLock.withLock { _streamStatus }
        }

        package override var streamError: Error? {
            stateLock.withLock { _streamError }
        }

        package override func open() {
            stateLock.withLock { _streamStatus = .open }
        }

        package override func close() {
            stateLock.withLock { _streamStatus = .closed }
            producerTask.cancel()
            buffer.cancel()
        }

        package override func schedule(in aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}

        package override func remove(from aRunLoop: RunLoop, forMode mode: RunLoop.Mode) {}

        package override func property(forKey key: Stream.PropertyKey) -> Any? {
            nil
        }

        package override func setProperty(_ property: Any?, forKey key: Stream.PropertyKey) -> Bool {
            false
        }

        // MARK: - InputStream overrides

        package override var hasBytesAvailable: Bool {
            buffer.hasBytesAvailable
        }

        package override func read(_ destination: UnsafeMutablePointer<UInt8>, maxLength length: Int) -> Int {
            let (written, error) = buffer.read(into: destination, maxLength: length)

            if let error {
                stateLock.withLock {
                    _streamError = error
                    _streamStatus = .error
                }
                return -1
            }

            if written == .zero {
                stateLock.withLock { _streamStatus = .atEnd }
            }

            return written
        }

        /// Always declines -- an O(1) direct-pointer shortcut only makes sense for a stream
        /// backed by one contiguous, already-fully-available buffer, which this one, filled
        /// incrementally and concurrently by the producer `Task`, is not. `InputStream`'s own
        /// docs say subclassers may return `false` when it isn't appropriate.
        package override func getBuffer(
            _ buffer: UnsafeMutablePointer<UnsafeMutablePointer<UInt8>?>,
            length: UnsafeMutablePointer<Int>
        ) -> Bool {
            false
        }
    }
}

extension Internals.URLSessionUploadStream {

    /// The bounded producer/consumer queue `URLSessionUploadStream` reads from. Kept separate
    /// from the `InputStream` subclass so the backpressure logic itself -- the part actually
    /// worth getting right -- can be reasoned about (and tested) without an `InputStream`/
    /// `URLSession` round trip.
    ///
    /// Two-way backpressure, deliberately asymmetric in how each side waits:
    /// - The **producer** (the `Task` draining the source `AsyncSequence`) waits for room via a
    /// `CheckedContinuation` -- a genuine `async` suspension, costing no thread, appropriate
    /// since the producer runs on Swift concurrency's cooperative pool.
    /// - The **consumer** (`read(into:maxLength:)`, called synchronously by `URLSession` from a
    /// thread with no `async` context at all) waits for data via a `DispatchSemaphore` --
    /// `InputStream.read` is a blocking call by contract, so blocking its calling thread is
    /// exactly what it already signed up for.
    final class Buffer: @unchecked Sendable {

        // MARK: - Private properties

        private let highWaterMark: Int
        private let lock = Lock()
        private let dataAvailable = DispatchSemaphore(value: .zero)

        // MARK: - Unsafe properties (guarded by `lock`)

        private var queue: [Data] = []
        private var bufferedByteCount = Int.zero
        private var isFinished = false
        private var isCancelled = false
        private var failure: Error?
        private var roomContinuation: CheckedContinuation<Void, Never>?

        // MARK: - Inits

        init(highWaterMark: Int) {
            self.highWaterMark = highWaterMark
        }

        // MARK: - Internal properties

        var hasBytesAvailable: Bool {
            lock.withLock { !queue.isEmpty || !isFinished }
        }

        // MARK: - Producer-side methods (async)

        /// Suspends while the buffer already holds `highWaterMark` bytes, then appends `data`.
        /// A no-op once `cancel()` has been called.
        func push(_ data: Data) async {
            guard !data.isEmpty else { return }

            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeNow = lock.withLock { () -> Bool in
                    guard !isCancelled, bufferedByteCount >= highWaterMark else {
                        return true
                    }
                    roomContinuation = continuation
                    return false
                }

                if resumeNow {
                    continuation.resume()
                }
            }

            let shouldSignal = lock.withLock { () -> Bool in
                guard !isCancelled else { return false }
                queue.append(data)
                bufferedByteCount += data.count
                return true
            }

            if shouldSignal {
                dataAvailable.signal()
            }
        }

        /// Marks the source exhausted (`error == nil`) or failed. Either way, unblocks a
        /// `read(into:maxLength:)` currently waiting for more data.
        func finish(_ error: Error? = nil) {
            lock.withLock {
                isFinished = true
                failure = error
            }
            dataAvailable.signal()
        }

        /// Called from `InputStream.close()`/`deinit` -- releases a `read` blocked waiting for
        /// data and a `push` blocked waiting for room, without waiting for the producer to reach
        /// a natural stopping point on its own.
        func cancel() {
            let waitingForRoom: CheckedContinuation<Void, Never>? = lock.withLock {
                isCancelled = true
                defer { roomContinuation = nil }
                return roomContinuation
            }

            waitingForRoom?.resume()
            dataAvailable.signal()
        }

        // MARK: - Consumer-side methods (sync)

        /// Blocks the calling thread until at least one byte is available, the source has
        /// finished, or the buffer was cancelled -- matching `InputStream.read(_:maxLength:)`'s
        /// own blocking contract, which this directly backs.
        ///
        /// - Returns: `(0, nil)` at a clean end-of-stream (or after `cancel()`); `(0, error)` if
        /// the producer failed; otherwise the number of bytes actually written, `1...maxLength`.
        func read(into destination: UnsafeMutablePointer<UInt8>, maxLength: Int) -> (written: Int, error: Error?) {
            while lock.withLock({ queue.isEmpty && !isFinished && !isCancelled }) {
                dataAvailable.wait()
            }

            struct Outcome {
                var written = Int.zero
                var error: Error?
                var resumeRoom: CheckedContinuation<Void, Never>?
            }

            let outcome = lock.withLock { () -> Outcome in
                guard !isCancelled else {
                    return Outcome()
                }

                guard !queue.isEmpty else {
                    return Outcome(error: failure)
                }

                var result = Outcome()

                while result.written < maxLength, !queue.isEmpty {
                    let chunk = queue[0]
                    let toCopy = Swift.min(maxLength - result.written, chunk.count)
                    chunk.copyBytes(to: destination + result.written, count: toCopy)
                    bufferedByteCount -= toCopy

                    if toCopy == chunk.count {
                        queue.removeFirst()
                    } else {
                        queue[0] = chunk.subdata(in: toCopy..<chunk.count)
                    }

                    result.written += toCopy
                }

                if bufferedByteCount < highWaterMark, let waiting = roomContinuation {
                    roomContinuation = nil
                    result.resumeRoom = waiting
                }

                return result
            }

            outcome.resumeRoom?.resume()
            return (outcome.written, outcome.error)
        }
    }
}

#endif
