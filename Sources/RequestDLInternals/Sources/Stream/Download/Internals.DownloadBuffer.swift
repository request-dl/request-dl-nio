//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension Internals {

    package struct DownloadBuffer: Sendable {

        /// What `append` queues: a chunk the producer already holds in memory, or a buffer that
        /// still has to be read (and may sit behind the file system).
        fileprivate enum Income: Sendable {
            case chunk(Chunk)
            case buffer(Internals.AnyBuffer)

            var readableBytes: Int {
                switch self {
                case .chunk(let chunk):
                    return chunk.readableBytes
                case .buffer(let buffer):
                    return buffer.readableBytes
                }
            }
        }

        private final class Storage: @unchecked Sendable {

            // MARK: - Internal properties

            package let stream: Internals.AsyncStream<Chunk>
            package let flowControl: Internals.FlowControlWindow?

            // MARK: - Private properties

            // The queue is the only synchronization here. Parsing has to be serialized anyway
            // because it carries state across calls, and it has to stay off the event loop
            // that feeds it, so a second lock on top would only add a critical section that
            // dispatching resumes continuations inside of.
            //
            // At the priority of whoever creates the buffer, not a fixed low one: somebody is
            // awaiting these elements, and that is usually the task that made the buffer.
            // Producing at a lower priority than a consumer that waits for it is a priority
            // inversion: under load, a fixed `.utility` queue stayed unscheduled while the
            // consumer's own tasks kept running.
            private let queue = AsyncQueue()

            // The Knuth-Morris-Pratt "longest proper prefix that's also a suffix" table for the
            // separator, computed once up front. It lets `_appendBySeparator` backtrack a failed
            // match in O(1) amortized per incoming byte instead of rebuilding a candidate window
            // with an O(separator.count) shift on every single byte. Empty when the reading mode
            // isn't `.separator`.
            private let separatorLPS: [Int]

            // MARK: - Unsafe properties

            // Touched only from inside a queue operation. The queue serializes them and
            // establishes the ordering between them, so nothing else may read or write these.
            //
            // The bytes of an item that has not ended yet, waiting for the rest of it. `nil` once
            // the stream is over (closed or failed), which is how later appends know to do nothing.
            private var _pending: Data? = Data()
            private var _cacheStream: Internals.AsyncStream<Chunk>?

            // Starts as what the caller asked for. Only ever replaced by ``passThrough()``.
            private var _readingMode: Internals.DownloadStep.ReadingMode

            // How many leading bytes of the separator are currently matched against the tail of
            // what's been scanned so far (the KMP automaton's current state).
            //
            // It has to survive across calls: a separator can straddle two network packets, and
            // restarting the scan at zero on every call would never match one that does.
            private var _matchLength = 0

            // MARK: - Inits

            package init(
                readingMode: Internals.DownloadStep.ReadingMode,
                flowControl: Internals.FlowControlWindow?
            ) {
                self._readingMode = readingMode
                self.flowControl = flowControl

                if case .separator(let separator, _) = readingMode {
                    self.separatorLPS = Self.computeLPS(separator)
                } else {
                    self.separatorLPS = []
                }

                // The body is buffered until somebody starts reading it, which covers both the
                // live path, where bytes arrive long before the caller reaches for them, and
                // the cached path, where the whole body is dumped before the response object
                // even exists. From the first read on, only the gap between producer and reader
                // stays in memory instead of the entire download.
                //
                // That gap is only bounded when there is a `flowControl` window, and only by
                // a producer that honours it; see `append(_:)`.
                self.stream = .init(flowControl: flowControl)
            }

            // MARK: - Internal methods

            /// Attaches a cache stream.
            ///
            /// Queued like everything else so it is ordered against the appends. Setting it
            /// out of band would let chunks already dispatched miss the cache.
            package func cacheStream(_ cacheStream: Internals.AsyncStream<Chunk>) {
                queue.addOperation {
                    self._cacheStream = cacheStream
                }
            }

            /// Queues `income` for re-chunking.
            ///
            /// With a `flowControl` window, the bytes are charged right here, synchronously, and
            /// not only once they reach `stream`. The queue is a buffer in its own right: it
            /// runs on a task that can lag arbitrarily far behind the event loop feeding it, and
            /// a producer that only saw what had already reached `stream` could keep going
            /// while its backlog piled up in the queue instead.
            ///
            /// They are credited back once `_append` has run, by which point every one of them
            /// has either been dispatched into `stream` (charged again there, as it went in) or
            /// absorbed into `_pending` to wait for the rest of its chunk. The latter must not
            /// stay counted: a chunk that only completes with more input would otherwise hold
            /// the window shut against exactly the input it needs, forever. See
            /// `Internals.FlowControlWindow`'s "Liveness" section.
            fileprivate func append(_ income: Income) {
                let queuedBytes = income.readableBytes
                flowControl?.charge(queuedBytes)

                queue.addOperation {
                    await self._append(income)
                    self.flowControl?.credit(queuedBytes)
                }
            }

            /// Stops re-chunking from the next append on, ordered against them like everything else.
            package func passThrough() {
                queue.addOperation {
                    self._readingMode = .passthrough
                    self._matchLength = 0
                }
            }

            package func close() {
                queue.addOperation {
                    self._close()
                }
            }

            package func failed(_ error: Error) {
                queue.addOperation {
                    self._failed(error)
                }
            }

            package var queuePriorityForTesting: _Concurrency.TaskPriority {
                queue.priorityForTesting
            }

            /// Suspends until every queued operation has run.
            package func waitUntilIdle() async {
                await queue.waitUntilIdle()
            }

            // MARK: - Unsafe methods

            private func _append(_ income: Income) async {
                guard _pending != nil else {
                    return
                }

                do {
                    switch income {
                    case .chunk(let chunk):
                        // In memory already: nothing to read, and so nothing to suspend for.
                        try _consume(chunk.data)

                    case .buffer(let buffer):
                        var buffer = buffer

                        // A buffer behind the file system (a cached body) is read in blocks of
                        // ``readBlockSize``, so an entry is never pulled into memory whole, and
                        // one trip to the file serves many chunks instead of one each (a kilobyte
                        // by default). An in-memory one is read at once: there is no trip to
                        // save, and `.passthrough` is meant to hand it over as one piece.
                        let blockSize = buffer is Internals.DataBuffer ? Int.max : Self.readBlockSize

                        while buffer.readableBytes > .zero {
                            let block = try await Self.readableData(
                                &buffer,
                                count: min(buffer.readableBytes, blockSize)
                            )

                            try _consume(block)
                        }
                    }
                } catch {
                    // Ends the stream with the error and drops the accumulated bytes. Whatever
                    // still arrives is ignored, since there is no `_pending` left to put it in.
                    _failed(error)
                }
            }

            /// Cuts `block` according to the reading mode and dispatches what completes.
            ///
            /// Synchronous: a block is in memory by now, and the accumulator is a `Data`, so no
            /// step of cutting has anything to wait for. Chunks are dispatched in the order they
            /// are cut, which is the order of the stream.
            private func _consume(_ block: Data) throws {
                guard !block.isEmpty else {
                    return
                }

                switch _readingMode {
                case .passthrough:
                    _dispatch(.success(Chunk(block)))
                case .length(let length):
                    try _consumeByLength(block, length: length)
                case .separator(let separator, let maximumItemSize):
                    try _consumeBySeparator(block, separator: separator, maximumItemSize: maximumItemSize)
                }
            }

            /// Cuts chunks of `length` out of `block`, in memory.
            ///
            /// A chunk that fits inside the block while nothing is pending is cut straight from it
            /// (see ``Chunk/init(slicing:of:)`` for what that costs). Only the piece of a chunk that
            /// straddles two blocks goes through `_pending`, and a finished `_pending` is handed
            /// over as the chunk itself instead of being copied.
            ///
            /// - Throws: ``AsyncBytesReadError`` when `length` cannot make progress.
            private func _consumeByLength(_ block: Data, length: Int) throws {
                // No chunk size can make progress: reading would loop without ever filling one.
                guard length > .zero else {
                    throw AsyncBytesReadError()
                }

                var offset = block.startIndex

                while offset < block.endIndex {
                    let pendingCount = _pending?.count ?? .zero

                    if pendingCount == .zero, block.endIndex - offset >= length {
                        _dispatch(.success(Chunk(slicing: offset..<offset + length, of: block)))
                        offset += length
                        continue
                    }

                    let count = min(length - pendingCount, block.endIndex - offset)

                    _pending?.append(block[offset..<offset + count])
                    offset += count

                    if pendingCount + count == length {
                        _emit()
                    }
                }
            }

            /// Splits `block` on `separator`, emitting a chunk per occurrence with the separator
            /// included, exactly as before.
            ///
            /// Every incoming byte is copied once, either into an emitted chunk or into the remainder
            /// kept for the next call. Matching is done on a rolling window that survives across
            /// calls, so a separator split across two packets is still found and no trailing byte is
            /// dropped.
            ///
            /// - Throws: ``Internals/ReadingModeItemTooLargeError`` as soon as an item, separator
            ///   included, can no longer fit `maximumItemSize`: when the accumulated bytes pass
            ///   it without a separator, or when the separator ends an item that is over it.
            private func _consumeBySeparator(
                _ incoming: Data,
                separator: [UInt8],
                maximumItemSize: Int?
            ) throws {
                guard !separator.isEmpty else {
                    // Degenerate configuration: there is nothing to split on, so everything is
                    // remainder. Matching an empty window would otherwise emit once per byte.
                    _pending?.append(incoming)
                    return
                }

                var start = incoming.startIndex

                for index in incoming.indices {
                    let byte = incoming[index]

                    while _matchLength > 0, byte != separator[_matchLength] {
                        _matchLength = separatorLPS[_matchLength - 1]
                    }

                    if byte == separator[_matchLength] {
                        _matchLength += 1
                    }

                    guard _matchLength == separator.count else {
                        continue
                    }

                    let pendingCount = _pending?.count ?? .zero

                    // Checked before the bytes are copied: an item that is already too large
                    // is never copied into a chunk, and not delivered.
                    if let maximumItemSize, pendingCount + (index - start + 1) > maximumItemSize {
                        throw Internals.ReadingModeItemTooLargeError(maximumItemSize: maximumItemSize)
                    }

                    if pendingCount == .zero {
                        // The whole item is in this block: it becomes the chunk, with no
                        // accumulator in between.
                        _dispatch(.success(Chunk(slicing: start..<index + 1, of: incoming)))
                    } else {
                        _pending?.append(incoming[start...index])
                        _emit()
                    }

                    start = incoming.index(after: index)
                    _matchLength = 0
                }

                if start < incoming.endIndex {
                    // The rest belongs to an item that has not ended yet. If it is already over
                    // the maximum, it can only get larger.
                    if let maximumItemSize, (_pending?.count ?? .zero) + (incoming.endIndex - start) > maximumItemSize {
                        throw Internals.ReadingModeItemTooLargeError(maximumItemSize: maximumItemSize)
                    }

                    _pending?.append(incoming[start...])
                }
            }

            /// Precomputes the KMP failure table for `pattern`: `lps[i]` is the length of the
            /// longest proper prefix of `pattern[0...i]` that's also a suffix of it, which is
            /// exactly how far a failed match can safely fall back to without skipping a
            /// possible earlier match.
            private static func computeLPS(_ pattern: [UInt8]) -> [Int] {
                guard !pattern.isEmpty else {
                    return []
                }

                var lps = [Int](repeating: 0, count: pattern.count)
                var length = 0
                var i = 1

                while i < pattern.count {
                    if pattern[i] == pattern[length] {
                        length += 1
                        lps[i] = length
                        i += 1
                    } else if length != 0 {
                        length = lps[length - 1]
                    } else {
                        lps[i] = 0
                        i += 1
                    }
                }

                return lps
            }

            /// How much of the incoming buffer is read at once when cutting it into chunks.
            private static let readBlockSize = 65_536

            /// Reads `count` bytes that `buffer` has just reported it holds.
            ///
            /// `Internals.Buffer` answers `nil` for a read that failed, and that is also its answer
            /// at the end of the data. Told apart by the caller already knowing there is more: a
            /// `nil` for bytes that were reported readable is a failure (an encrypted entry whose
            /// tag no longer matches, a file removed after it was looked up, an I/O error), not the
            /// end. Taking it for the end would close the stream normally, and a body cut short
            /// would reach the reader as one that succeeded.
            ///
            /// - Throws: ``AsyncBytesReadError``.
            private static func readableData(_ buffer: inout Internals.AnyBuffer, count: Int) async throws -> Data {
                guard let data = await buffer.readData(count), !data.isEmpty else {
                    throw AsyncBytesReadError()
                }

                return data
            }

            /// Dispatches the accumulated bytes as one chunk and starts over with an empty
            /// accumulator.
            ///
            /// The accumulator itself is what becomes the chunk, not a copy of it: `Data` is a
            /// value over shared storage, so handing it over costs nothing, and the replacement is
            /// a fresh one. That is also what keeps the allocation from staying pinned at the size
            /// of the single largest chunk (one unusually large `.length` window, or one long
            /// line before a `.separator`) for the rest of the connection, which reusing one
            /// accumulator for every chunk did unless it was cleared.
            private func _emit() {
                // `_pending` is only `nil` once the stream has ended, and `_append` stops before
                // cutting anything then, so this is always taken; it stays a check because the
                // alternative to skipping an emit would be to dispatch bytes of a stream that has
                // already finished.
                if let pending = _pending {
                    _pending = Data()

                    _dispatch(.success(Chunk(pending)))
                }
            }

            private func _close() {
                guard let pending = _pending else {
                    return
                }

                if !pending.isEmpty {
                    _dispatch(.success(Chunk(pending)))
                }

                _pending = nil
                _matchLength = 0

                stream.close()
                _cacheStream?.close()
            }

            private func _failed(_ error: Error) {
                _pending = nil
                _matchLength = 0

                _dispatch(.failure(error))
            }

            private func _dispatch(_ chunk: Result<Chunk, Error>) {
                stream.append(chunk)

                guard let cacheStream = _cacheStream else {
                    return
                }

                // The cache writer is not the reader: `flowControl` meters `stream` alone, and the
                // network is never held back for a disk. So a writer that cannot keep up would let
                // this stream grow to the whole body. Rather than that, or slowing the download
                // down to the disk's pace, caching is given up once the writer is further behind
                // than its own window allows.
                //
                // Ended with a failure, not closed: closing would present the part of the body
                // that did arrive as a complete one, and it would be stored as the response.
                if case .success = chunk, let window = cacheStream.flowControlWindow, !window.isWritable {
                    _cacheStream = nil
                    cacheStream.append(.failure(Internals.CacheBacklogExceededError(limit: window.highWatermark)))
                    return
                }

                // The same value goes to both streams. They share its bytes, and nothing can write
                // them, so no ownership has to be settled between the reader and the cache.
                cacheStream.append(chunk)
            }
        }

        // MARK: - Internal properties

        package var stream: Internals.AsyncStream<Chunk> {
            storage.stream
        }

        /// The window metering `stream`, which the producer feeding `append(_:)` consults to
        /// know when to stop. `nil` unless one was passed in at construction.
        package var flowControl: Internals.FlowControlWindow? {
            storage.flowControl
        }

        // MARK: - Private properties

        private let storage: Storage
        private let observer: Internals.ExecutionObserver?

        // MARK: - Inits

        /// - Parameter flowControl: Meters `stream` so its producer can be paused rather than run
        ///   arbitrarily far ahead of the reader. Only worth passing where the producer can
        ///   actually honour it: today that is `Internals.ClientResponseReceiver`, whose NIO
        ///   delegate contract has a way to say "not yet", and
        ///   `Internals.URLSessionClient.pumpResponseBody`, which pulls from a
        ///   `URLSession.AsyncBytes` only while there is room. A producer that ignores the window
        ///   (the cached-response replay, the mocked task, the `URLSession` `didReceive data:`
        ///   delegate behind the non-`SessionTask` overloads) gains nothing from one and passes
        ///   `nil`, which leaves it unmetered.
        ///
        /// - Parameter observer: Counts every byte handed to ``append(_:)``, the one place both
        ///   executors (and a continuation after a lost connection) feed the response body
        ///   through, so it sees what came in off the network rather than what a reader took.
        package init(
            readingMode: Internals.DownloadStep.ReadingMode,
            flowControl: Internals.FlowControlWindow? = nil,
            observer: Internals.ExecutionObserver? = nil
        ) async {
            self.storage = .init(readingMode: readingMode, flowControl: flowControl)
            self.observer = observer
        }

        /// ``init(readingMode:flowControl:observer:)`` for a caller that cannot suspend.
        ///
        /// Nothing in construction needs to: the first buffer is held in memory.
        package init(
            immediate readingMode: Internals.DownloadStep.ReadingMode,
            flowControl: Internals.FlowControlWindow? = nil
        ) {
            self.storage = .init(readingMode: readingMode, flowControl: flowControl)
            self.observer = nil
        }

        // MARK: - Internal methods

        /// Appends a body part the producer already holds in memory, which is what both network
        /// executors do: nothing is read out of it or written into another buffer on the way.
        package func append(_ chunk: Chunk) {
            observer?.didReceive(chunk.readableBytes)
            storage.append(.chunk(chunk))
        }

        /// Appends a buffer of any kind. For one that is not simply in memory (a cached body, read
        /// back from the file system), ``append(_:)-(Chunk)`` is the call for what is.
        package func append(_ incomeBytes: Internals.AnyBuffer) {
            observer?.didReceive(incomeBytes.readableBytes)
            storage.append(.buffer(incomeBytes))
        }

        package func close() {
            storage.close()
        }

        /// Forwards what is appended from now on without re-chunking it, whatever reading mode this
        /// was made with.
        ///
        /// For a body that is about to be transformed (decompressed) before anybody reads it: the
        /// reading mode is meant for what the reader gets, so cutting the input into chunks that
        /// the transformation only takes apart again is pure copying. Whatever sits downstream
        /// cuts the output instead, see `Internals.ManualDecompressionDispatch.resolvedStream`.
        ///
        /// Meant to be called before the first byte is appended: bytes already waiting in a
        /// partly filled chunk stay where they are until the next close.
        package func passThrough() {
            storage.passThrough()
        }

        package func failed(_ error: Error) {
            storage.failed(error)
        }

        // Not `mutating`: the state lives in a class, so requiring `var` at the call site would
        // only advertise a mutation that never happens.
        package func cacheStream(_ cacheStream: Internals.AsyncStream<Chunk>) {
            storage.cacheStream(cacheStream)
        }

        /// Suspends until every queued operation has run. Meant for tests.
        package func waitUntilIdle() async {
            await storage.waitUntilIdle()
        }

        /// The priority the buffer's operations run at. Meant for tests.
        package var queuePriorityForTesting: _Concurrency.TaskPriority {
            storage.queuePriorityForTesting
        }
    }
}

// MARK: - Internals.DownloadStep extension

extension Internals.DownloadStep {

    package enum ReadingMode: Sendable, Hashable {
        /// Delivers each received part as it arrives, without cutting or joining anything.
        ///
        /// For a reader that concatenates the whole body anyway, where re-chunking would only be
        /// copying: one chunk per part the network (or a block of a cached body) delivered, so the
        /// sizes are whatever the transport happens to produce.
        case passthrough

        case length(Int)

        /// Items end at `separator`, which they include. `maximumItemSize` is the most bytes one
        /// item may take, separator included; `nil` puts no limit on it.
        case separator([UInt8], maximumItemSize: Int? = nil)
    }
}

extension Internals {

    /// Ends a cache tee whose writer fell further behind the download than its window allows. See
    /// ``Internals/DownloadBuffer/cacheBacklogLimit``.
    package struct CacheBacklogExceededError: Swift.Error, Sendable, Hashable, CustomStringConvertible {

        /// The most bytes the writer was allowed to be behind, the window's high watermark.
        package let limit: Int

        package var description: String {
            "The cache writer fell more than \(limit) bytes behind the download."
        }

        package init(limit: Int) {
            self.limit = limit
        }
    }
}

extension Internals.DownloadBuffer {

    /// The most bytes a cache tee may hold that its writer has not taken yet.
    ///
    /// Sized for a writer that is momentarily slow, not for one that is slow throughout: the
    /// window this meters sits beside the download's own (1 MiB), and the body only ever sits in
    /// memory twice over once the writer is behind, so this is the most extra memory caching can
    /// cost a download.
    package static let cacheBacklogLimit = 16 * 1_024 * 1_024

    /// A stream for ``cacheStream(_:)`` that is metered against ``cacheBacklogLimit``.
    package static func makeCacheStream() -> Internals.AsyncStream<Internals.Chunk> {
        .init(
            flowControl: Internals.FlowControlWindow(
                highWatermark: cacheBacklogLimit,
                lowWatermark: cacheBacklogLimit / 2
            )
        )
    }
}

extension Internals {

    /// Thrown to the reader of a download read with a separator when an item grew past the
    /// `maximumItemSize` without ending.
    package struct ReadingModeItemTooLargeError: Swift.Error, Sendable, Hashable, CustomStringConvertible {

        /// The limit that was exceeded, in bytes.
        package let maximumItemSize: Int

        package var description: String {
            "An item read with a separator grew past \(maximumItemSize) bytes without ending."
        }

        package init(maximumItemSize: Int) {
            self.maximumItemSize = maximumItemSize
        }
    }
}
