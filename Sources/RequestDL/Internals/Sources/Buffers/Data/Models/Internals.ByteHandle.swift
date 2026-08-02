//
// See LICENSE for this package's licensing information.
//

import NIOCore
import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import protocol Foundation.DataProtocol
#endif

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
            try lock.withLock { () throws -> Data? in
                guard !_isClosed else {
                    throw ClosedError()
                }

                // Reporting rather than returning nil. A read on a write handle is a wiring
                // mistake, and the silent nil made it indistinguishable from an empty buffer,
                // which is the hardest possible shape to debug.
                guard case .read = mode else {
                    throw InvalidModeError(requested: .read, actual: mode)
                }

                guard count > .zero else {
                    return nil
                }

                let index = Int(_index)

                // Seeking and reading are one operation. There is always a second handle
                // writing to the same `ByteURL`, and moving the indices one statement at a
                // time let the two interleave, which reads from whatever offset the other
                // side happened to leave behind.
                let data = url.withStorage { buffer, writtenBytes -> Data? in
                    // Out of range is a possible outcome of a truncated or concurrently reset
                    // buffer, not a programming error, so it reports rather than traps. The
                    // previous `precondition` here turned every such race into a crash.
                    guard index >= .zero, index + count <= writtenBytes else {
                        return nil
                    }

                    buffer.moveWriterIndex(to: writtenBytes)
                    buffer.moveReaderIndex(to: index)

                    return buffer.readData(length: count)
                }

                _index = UInt64((data == nil ? .zero : count) + index)
                return data
            }
        }

        func write<T: DataProtocol>(contentsOf data: T) throws {
            try lock.withLockVoid {
                guard !_isClosed else {
                    throw ClosedError()
                }

                guard case .write = mode else {
                    throw InvalidModeError(requested: .write, actual: mode)
                }

                let index = Int(_index)

                // Same reasoning as `read`, plus the cost: mutating the buffer in place keeps
                // its storage uniquely referenced, so appending no longer copies everything
                // written so far on every call.
                let written = url.withStorage { buffer, writtenBytes -> Int in
                    buffer.moveReaderIndex(to: .zero)

                    let gap = index - buffer.writerIndex

                    if gap > .zero {
                        // Seeked past the end. A file handle leaves a hole there and carries
                        // on, so match it. Handing the index straight to `moveWriterIndex`
                        // trips NIO's capacity precondition and takes the process down.
                        _ = buffer.writeRepeatingByte(.zero, count: gap)
                    } else {
                        buffer.moveWriterIndex(to: index)
                    }

                    let written = buffer.writeData(data)
                    writtenBytes = max(writtenBytes, buffer.writerIndex)

                    return written
                }

                _index += UInt64(written)
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

    fileprivate struct ClosedError: Error, CustomStringConvertible {

        var description: String {
            "This byte handle has already been closed"
        }
    }

    fileprivate struct InvalidModeError: Error, CustomStringConvertible {

        let requested: Mode
        let actual: Mode

        var description: String {
            "Attempted to \(requested) through a byte handle opened for \(actual)"
        }
    }
}

extension Internals.ByteHandle {

    fileprivate enum Mode: CustomStringConvertible {

        case write
        case read

        var description: String {
            switch self {
            case .write:
                return "writing"
            case .read:
                return "reading"
            }
        }
    }
}
