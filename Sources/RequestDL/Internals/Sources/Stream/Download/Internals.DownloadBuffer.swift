//
// See LICENSE for this package's licensing information.
//

import NIOCore
import SwiftAsyncStream

extension Internals {

    struct DownloadBuffer: Sendable {

        private final class Storage: @unchecked Sendable {

            // MARK: - Internal properties

            let stream: Internals.AsyncStream<DataBuffer>

            // MARK: - Private properties

            // The queue is the only synchronization here. Parsing has to be serialized anyway
            // because it carries state across calls, and it has to stay off the event loop
            // that feeds it, so a second lock on top would only add a critical section that
            // dispatching resumes continuations inside of.
            //
            // `.utility` rather than `.background`: somebody is awaiting these elements, and
            // background QoS is deferred under thermal or low power pressure. Producing at the
            // lowest priority for a consumer that is usually higher is a priority inversion.
            private let queue = AsyncQueue(priority: .utility)
            private let readingMode: Internals.DownloadStep.ReadingMode

            // MARK: - Unsafe properties

            // Touched only from inside a queue operation. The queue serializes them and
            // establishes the ordering between them, so nothing else may read or write these.
            private var _buffer: DataBuffer?
            private var _cacheStream: Internals.AsyncStream<DataBuffer>?

            // Trailing bytes of the current chunk, at most `separator.count` of them.
            //
            // It has to survive across calls: a separator can straddle two network packets,
            // and a window rebuilt per call would never match one that does.
            private var _window = [UInt8]()

            // MARK: - Inits

            init(readingMode: Internals.DownloadStep.ReadingMode) async {
                self._buffer = await DataBuffer()
                self.readingMode = readingMode

                // The body is buffered until somebody starts reading it, which covers both the
                // live path, where bytes arrive long before the caller reaches for them, and
                // the cached path, where the whole body is dumped before the response object
                // even exists. From the first read on, only the gap between producer and reader
                // stays in memory instead of the entire download.
                self.stream = .init(bufferingPolicy: .untilFirstIteration)
            }

            // MARK: - Internal methods

            /// Attaches a cache stream.
            ///
            /// Queued like everything else so it is ordered against the appends. Setting it
            /// out of band would let chunks already dispatched miss the cache.
            func cacheStream(_ cacheStream: Internals.AsyncStream<DataBuffer>) {
                queue.addOperation {
                    self._cacheStream = cacheStream
                }
            }

            func append(_ incomeBytes: Internals.AnyBuffer) {
                queue.addOperation {
                    await self._append(incomeBytes)
                }
            }

            func close() {
                queue.addOperation {
                    await self._close()
                }
            }

            func failed(_ error: Error) {
                queue.addOperation {
                    self._failed(error)
                }
            }

            /// Suspends until every queued operation has run.
            func waitUntilIdle() async {
                await queue.waitUntilIdle()
            }

            // MARK: - Unsafe methods

            private func _append(_ incomeBytes: Internals.AnyBuffer) async {
                guard var buffer = _buffer else {
                    return
                }

                defer { self._buffer = buffer }

                var incomeBytes = incomeBytes

                switch readingMode {
                case .length(let length):
                    await _appendByLength(&incomeBytes, length: length, into: &buffer)
                case .separator(let separator):
                    await _appendBySeparator(&incomeBytes, separator: separator, into: &buffer)
                }
            }

            private func _appendByLength(
                _ incomeBytes: inout Internals.AnyBuffer,
                length: Int,
                into buffer: inout DataBuffer
            ) async {
                while incomeBytes.readableBytes > .zero {
                    let receivedBytes = incomeBytes.readableBytes
                    let currentBytes = buffer.readableBytes

                    let availableBytes = length - currentBytes
                    let readableBytes = receivedBytes > availableBytes ? availableBytes : receivedBytes

                    if let data = await incomeBytes.readData(readableBytes) {
                        await buffer.writeData(data)
                    } else {
                        break
                    }

                    if buffer.readableBytes == length {
                        await _emit(&buffer)
                    }
                }
            }

            /// Splits the incoming bytes on `separator`, emitting a chunk per occurrence with
            /// the separator included, exactly as before.
            ///
            /// Every incoming byte is written to `buffer` exactly once, either as part of an
            /// emitted chunk or as the remainder kept for the next call. Matching is done on a
            /// rolling window that survives across calls, so a separator split across two
            /// packets is still found and no trailing byte is dropped.
            private func _appendBySeparator(
                _ incomeBytes: inout Internals.AnyBuffer,
                separator: [UInt8],
                into buffer: inout DataBuffer
            ) async {
                guard
                    incomeBytes.readableBytes > .zero,
                    let incoming = await incomeBytes.readBytes(incomeBytes.readableBytes)
                else { return }

                guard !separator.isEmpty else {
                    // Degenerate configuration: there is nothing to split on, so everything is
                    // remainder. Matching an empty window would otherwise emit once per byte.
                    await buffer.writeBytes(incoming)
                    return
                }

                var start = incoming.startIndex

                for index in incoming.indices {
                    _window.append(incoming[index])

                    if _window.count > separator.count {
                        _window.removeFirst()
                    }

                    guard _window == separator else {
                        continue
                    }

                    await buffer.writeBytes(Array(incoming[start...index]))
                    start = incoming.index(after: index)

                    await _emit(&buffer)
                    _window.removeAll(keepingCapacity: true)
                }

                if start < incoming.endIndex {
                    await buffer.writeBytes(Array(incoming[start...]))
                }
            }

            /// Dispatches the accumulated bytes as one chunk and resets the buffer.
            private func _emit(_ buffer: inout DataBuffer) async {
                var dataBuffer = await DataBuffer()
                await dataBuffer.writeBuffer(&buffer)

                _dispatch(.success(dataBuffer))

                buffer.moveReaderIndex(to: .zero)
                buffer.moveWriterIndex(to: .zero)
            }

            private func _close() async {
                guard var buffer = _buffer else {
                    return
                }

                if let data = await buffer.readData(buffer.readableBytes) {
                    await _dispatch(.success(.init(data)))
                }

                self._buffer = nil
                _window.removeAll()

                stream.close()
                _cacheStream?.close()
            }

            private func _failed(_ error: Error) {
                _buffer = nil
                _window.removeAll()

                _dispatch(.failure(error))
            }

            private func _dispatch(_ dataBuffer: Result<DataBuffer, Error>) {
                stream.append(dataBuffer)
                _cacheStream?.append(dataBuffer)
            }
        }

        // MARK: - Internal properties

        var stream: Internals.AsyncStream<DataBuffer> {
            storage.stream
        }

        // MARK: - Private properties

        private let storage: Storage

        // MARK: - Inits

        init(readingMode: Internals.DownloadStep.ReadingMode) async {
            self.storage = await .init(readingMode: readingMode)
        }

        // MARK: - Internal methods

        func append(_ incomeBytes: Internals.AnyBuffer) {
            storage.append(incomeBytes)
        }

        func close() {
            storage.close()
        }

        func failed(_ error: Error) {
            storage.failed(error)
        }

        // No longer `mutating`: the state lives in a class, so requiring `var` at the call
        // site only advertised a mutation that never happened.
        func cacheStream(_ cacheStream: Internals.AsyncStream<DataBuffer>) {
            storage.cacheStream(cacheStream)
        }

        /// Suspends until every queued operation has run. Meant for tests.
        func waitUntilIdle() async {
            await storage.waitUntilIdle()
        }
    }
}

// MARK: - Internals.DownloadStep extension

extension Internals.DownloadStep {

    enum ReadingMode: Sendable, Hashable {
        case length(Int)
        case separator([UInt8])
    }
}
