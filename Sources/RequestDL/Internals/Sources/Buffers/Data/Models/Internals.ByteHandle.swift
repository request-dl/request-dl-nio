/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    final class ByteHandle: @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()

        private let mode: Mode
        private let url: ByteURL

        // MARK: - Unsafe properties

        private var _isClosed = false
        private var _index: UInt64 = .zero

        // MARK: - Inits

        init(forWritingTo url: ByteURL) {
            self.mode = .write
            self.url = url
        }

        init(forReadingFrom url: ByteURL) {
            self.mode = .read
            self.url = url
        }

        // MARK: - Methods

        func seek(toOffset offset: UInt64) throws {
            try lock.withLockVoid {
                precondition(offset >= .zero)

                guard !_isClosed else {
                    throw ClosedError()
                }

                _index = offset
            }
        }

        func offset() throws -> UInt64 {
            try lock.withLock {
                guard !_isClosed else {
                    throw ClosedError()
                }

                return _index
            }
        }

        func read(upToCount count: Int) throws -> Data? {
            try lock.withLock {
                precondition(count >= .zero)

                guard !_isClosed else {
                    throw ClosedError()
                }

                switch mode {
                case .write:
                    return nil
                case .read:
                    guard count > .zero else {
                        return nil
                    }

                    let index = Int(_index)
                    precondition(count + index <= url.writtenBytes)

                    url.buffer.moveWriterIndex(to: url.writtenBytes)
                    url.buffer.moveReaderIndex(to: index)

                    let data = url.buffer.readData(length: count)
                    _index = UInt64((data == nil ? .zero : count) + index)
                    return data
                }
            }
        }

        func write<T: DataProtocol>(contentsOf data: T) throws {
            try lock.withLockVoid {
                guard !_isClosed else {
                    throw ClosedError()
                }

                switch mode {
                case .write:
                    let index = Int(_index)

                    url.buffer.moveReaderIndex(to: .zero)
                    url.buffer.moveWriterIndex(to: index)

                    let written = url.buffer.writeData(data)
                    url.writtenBytes = max(url.writtenBytes, url.buffer.writerIndex)

                    self._index += UInt64(written)
                case .read:
                    return
                }
            }
        }

        func close() throws {
            try lock.withLockVoid {
                guard !_isClosed else {
                    throw ClosedError()
                }

                _isClosed = true
            }
        }
    }
}

extension Internals.ByteHandle {

    fileprivate struct ClosedError: Error {

        init() {}
    }
}

extension Internals.ByteHandle {

    fileprivate enum Mode {
        case write
        case read
    }
}
