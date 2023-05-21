/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    struct DownloadBuffer: Sendable {

        private final class Storage: @unchecked Sendable {

            // MARK: - Internal properties

            let stream: Internals.AsyncStream<DataBuffer>

            // MARK: - Private properties

            private let lock = Lock()

            private let queue = AsyncQueue(priority: .background)
            private let readingMode: Internals.Response.ReadingMode

            // MARK: - Unsafe properties

            private var _buffer: DataBuffer?
            private var _cacheStream: Internals.AsyncStream<DataBuffer>?

            // MARK: - Init {

            init(readingMode: Internals.Response.ReadingMode) {
                self._buffer = DataBuffer()
                self.readingMode = readingMode
                self.stream = .init()
            }

            // MARK: - Internal methods

            func cacheStream(_ cacheStream: Internals.AsyncStream<DataBuffer>) {
                lock.withLockVoid {
                    _cacheStream = cacheStream
                }
            }

            func append(_ incomeBytes: Internals.AnyBuffer) {
                queue.addOperation {
                    self.lock.withLockVoid {
                        self._append(incomeBytes)
                    }
                }
            }

            func close() {
                queue.addOperation {
                    self.lock.withLockVoid {
                        self._close()
                    }
                }
            }

            func failed(_ error: Error) {
                queue.addOperation {
                    self.lock.withLockVoid {
                        self._failed(error)
                    }
                }
            }

            // MARK: - Unsafe methods

            private func _append(_ incomeBytes: Internals.AnyBuffer) {
                guard var buffer = _buffer else {
                    return
                }

                defer { self._buffer = buffer }

                var incomeBytes = incomeBytes

                switch readingMode {
                case .length(let length):
                    while incomeBytes.readableBytes > .zero {
                        let receivedBytes = incomeBytes.readableBytes
                        let currentBytes = buffer.readableBytes

                        let availableBytes = length - currentBytes
                        let readableBytes = receivedBytes > availableBytes ? availableBytes : receivedBytes

                        if let data = incomeBytes.readData(readableBytes) {
                            buffer.writeData(data)
                        } else {
                            break
                        }

                        if buffer.readableBytes == length {
                            var dataBuffer = DataBuffer()
                            dataBuffer.writeBuffer(&buffer)

                            _dispatch(.success(dataBuffer))

                            buffer.moveReaderIndex(to: .zero)
                            buffer.moveWriterIndex(to: .zero)
                        }
                    }
                case .separator(let separator):
                    let length = separator.count

                    while let bytes = incomeBytes.readBytes(length) {
                        buffer.writeBytes(bytes)

                        guard bytes == separator else {
                            let index = incomeBytes.readerIndex - (length - 1)
                            incomeBytes.moveReaderIndex(to: index)
                            continue
                        }

                        var dataBuffer = DataBuffer()
                        dataBuffer.writeBuffer(&buffer)

                        _dispatch(.success(dataBuffer))

                        buffer.moveReaderIndex(to: .zero)
                        buffer.moveWriterIndex(to: .zero)
                    }
                }
            }

            private func _close() {
                guard var buffer = _buffer else {
                    return
                }

                if let data = buffer.readData(buffer.readableBytes) {
                    _dispatch(.success(.init(data)))
                }

                self._buffer = nil
                stream.close()
                _cacheStream?.close()
            }

            private func _failed(_ error: Error) {
                _buffer = nil
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

        init(readingMode: Internals.Response.ReadingMode) {
            self.storage = .init(readingMode: readingMode)
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

        mutating func cacheStream(_ cacheStream: Internals.AsyncStream<DataBuffer>) {
            storage.cacheStream(cacheStream)
        }
    }
}

// MARK: - Internals.Response extension

extension Internals.Response {

    enum ReadingMode: Sendable, Hashable {
        case length(Int)
        case separator([UInt8])
    }
}
