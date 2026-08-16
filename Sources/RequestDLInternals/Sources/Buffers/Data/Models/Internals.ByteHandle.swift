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

    /// A `FileHandle` shaped cursor over an ``Internals/ByteURL``.
    ///
    /// One handle is opened per direction, so there are always two of them over the same bytes.
    /// The offset is per handle; the bytes are not. Everything that touches both the offset and
    /// the store happens inside a single critical section, because the other handle is free to
    /// move the store in between two separate ones.
    ///
    /// Synchronous throughout. There is no I/O here, only memory, so nothing to suspend for.
    package final class ByteHandle: @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()

        private let mode: Mode
        private let url: ByteURL

        // MARK: - Unsafe properties

        private var _isClosed = false
        private var _index: UInt64 = .zero

        // MARK: - Inits

        package init(forWritingTo url: ByteURL) {
            self.mode = .write
            self.url = url
        }

        package init(forReadingFrom url: ByteURL) {
            self.mode = .read
            self.url = url
        }

        // MARK: - Methods

        /// Moves the offset the next operation will address.
        ///
        /// Seeking past the end is allowed, and matches a file handle: a write there fills the
        /// gap with zeros first.
        package func seek(toOffset offset: UInt64) throws {
            try lock.withLockVoid {
                guard !_isClosed else {
                    throw ClosedError()
                }

                _index = offset
            }
        }

        package func offset() throws -> UInt64 {
            try lock.withLock {
                guard !_isClosed else {
                    throw ClosedError()
                }

                return _index
            }
        }

        /// Reads up to `count` bytes from the current offset, advancing it by what arrived.
        ///
        /// - Returns: `nil` at or past the end of the store, otherwise the bytes available,
        /// which may be fewer than `count`.
        /// - Throws: ``InvalidModeError`` on a handle opened for writing.
        package func read(upToCount count: Int) throws -> Data? {
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
                    // buffer, not a programming error, so this reports rather than traps —
                    // must not be a `precondition`, which would turn every such race into a
                    // crash.
                    guard index >= .zero, index < writtenBytes else {
                        return nil
                    }

                    // Honouring "up to": asking for more than is left must not answer `nil`,
                    // which would make a partial tail indistinguishable from EOF.
                    let length = min(count, writtenBytes - index)

                    buffer.moveWriterIndex(to: writtenBytes)
                    buffer.moveReaderIndex(to: index)

                    // `readSlice` and a view, not `readData`. The `Data` returning members of
                    // `ByteBuffer` live in `NIOFoundationCompat`, which pulls in all of
                    // `Foundation` — exactly the dependency this type exists to avoid.
                    return buffer.readSlice(length: length).map { Data($0.readableBytesView) }
                }

                _index = UInt64(index + (data?.count ?? .zero))
                return data
            }
        }

        /// Writes at the current offset, advancing it by the byte count.
        ///
        /// - Throws: ``InvalidModeError`` on a handle opened for reading.
        package func write<Bytes: DataProtocol>(contentsOf data: Bytes) throws {
            try lock.withLockVoid {
                guard !_isClosed else {
                    throw ClosedError()
                }

                guard case .write = mode else {
                    throw InvalidModeError(requested: .write, actual: mode)
                }

                let index = Int(_index)

                // Same reasoning as `read`, plus the cost: mutating the buffer in place keeps
                // its storage uniquely referenced, so appending does not copy everything
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

                    // `writeBytes`, not `writeData`, for the `NIOFoundationCompat` reason
                    // above. `DataProtocol` is a collection of `UInt8`, so it fits.
                    let written = buffer.writeBytes(data)

                    // A write in the middle rewinds the writer index, so the count has to be a
                    // high water mark rather than the current position.
                    writtenBytes = max(writtenBytes, buffer.writerIndex)

                    return written
                }

                _index += UInt64(written)
            }
        }

        package func close() throws {
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

        package var description: String {
            "This byte handle has already been closed"
        }
    }

    fileprivate struct InvalidModeError: Error, CustomStringConvertible {

        package let requested: Mode
        package let actual: Mode

        package var description: String {
            "Attempted to \(requested) through a byte handle opened for \(actual)"
        }
    }
}

extension Internals.ByteHandle {

    fileprivate enum Mode: CustomStringConvertible {

        case write
        case read

        package var description: String {
            switch self {
            case .write:
                return "writing"
            case .read:
                return "reading"
            }
        }
    }
}
