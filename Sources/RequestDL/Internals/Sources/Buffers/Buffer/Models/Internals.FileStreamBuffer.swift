//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOFileSystem
import SwiftAsyncStream
import SystemPackage

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import protocol Foundation.DataProtocol
#endif

extension Internals {

    /// A stream over a file, backed by a single `NIOFileSystem` handle.
    ///
    /// ## Positioning
    ///
    /// Every call here addresses an absolute offset, `readChunk(fromAbsoluteOffset:)` and
    /// `write(toAbsoluteOffset:)` rather than a stream position plus `read`/`write`. The offset
    /// this type reports is bookkeeping for the protocol, not state the kernel shares, so
    /// nothing else can move the file position underneath an operation in flight.
    ///
    /// ## Blocking
    ///
    /// `NIOFileSystem` runs the underlying syscall on its own `NIOThreadPool`, not on whichever
    /// Swift Concurrency cooperative thread called in here. A prior revision called
    /// `SystemPackage.FileDescriptor` directly, which ran the syscall in place on that
    /// cooperative thread — harmless for one caller, but under `swift-testing`'s parallel test
    /// execution enough concurrent callers saturate the fixed-size cooperative pool, and a
    /// critical section merely waiting for a worker thread looks identical to one genuinely
    /// stuck to `AsyncLock.Watchdog`, which measures wall time, not CPU time. `DiskStorage`
    /// already made this move for its metadata files; this brings the byte level stream in line.
    final class FileStreamBuffer: @unchecked Sendable, StreamBuffer {

        typealias URL = Internals.FileBufferURL

        // MARK: - Private types

        /// A file is opened for reading or for writing, never both, matching the two inits
        /// below. `NIOFileSystem` hands back a different concrete handle type per direction.
        private enum Handle: Sendable {
            case read(ReadFileHandle)
            case write(WriteFileHandle)
        }

        // MARK: - Internal properties

        var offset: UInt64 {
            get async throws {
                await lock.withLock { _offset }
            }
        }

        // MARK: - Private static properties

        /// Flags a seek/read/write/close that is still running after 5s. Development builds
        /// only — see `AsyncLock.Watchdog`.
        #if DEBUG
        private static let watchdog: AsyncLock.Watchdog? = .init(seconds: 5) {
            Internals.assertionFailure($0)
        }
        #else
        private static let watchdog: AsyncLock.Watchdog? = nil
        #endif

        // MARK: - Private properties

        private let lock = AsyncLock(watchdog: watchdog)
        private let handle: Handle

        // MARK: - Unsafe properties

        private var _offset: UInt64 = .zero
        private var _isClosed = false

        // MARK: - Inits

        /// - Throws: Whatever `NIOFileSystem` throws when the file is not there. Callers are
        /// expected to check availability first and treat the throw as an empty read.
        init(readingFrom url: URL) async throws {
            handle = .read(try await Internals.fileSystem.openFile(forReadingAt: url.path))
        }

        /// Opens for writing, creating the file when it does not exist.
        ///
        /// - Important: Must not pass `.newFile(replaceExisting: true)` — that would empty the
        /// file every time the storage lazily opens its output stream, so the first write to an
        /// existing file would destroy it and then leave a zero filled gap where the old content
        /// had been. `.modifyFile` opens an existing file untouched and only creates one that is
        /// missing.
        init(writingTo url: URL) async throws {
            handle = .write(
                try await Internals.fileSystem.openFile(
                    forWritingAt: url.path,
                    options: .modifyFile(createIfNecessary: true, permissions: .ownerReadWrite)
                )
            )
        }

        // MARK: - Internal methods

        /// Moves the offset the next operation will address.
        ///
        /// Cheap, and never fails. Seeking past the end is allowed: a write there leaves a hole,
        /// and a read there comes back empty.
        func seek(to offset: UInt64) async throws {
            await lock.withLock { _offset = offset }
        }

        /// Writes every byte of `data`, looping over short writes.
        func writeData<Bytes: DataProtocol & Sendable>(_ data: Bytes) async throws {
            let bytes = Data(data)

            guard !bytes.isEmpty else {
                return
            }

            guard case .write(let writeHandle) = handle else {
                return
            }

            try await lock.withLock {
                var written = 0

                while written < bytes.count {
                    // Checked once per short-write retry rather than only on entry, so a large
                    // write cancelled partway through does not pay for every remaining chunk.
                    try Task.checkCancellation()

                    let count = try await writeHandle.write(
                        contentsOf: bytes[written...],
                        toAbsoluteOffset: Int64(_offset) + Int64(written)
                    )

                    // A zero length write with a non empty buffer is not progress, and looping
                    // on it spins forever.
                    guard count > .zero else {
                        throw Errno.ioError
                    }

                    written += Int(count)
                }

                _offset += UInt64(written)
            }
        }

        /// Reads up to `length` bytes, looping over short reads until EOF.
        ///
        /// - Important: Must not issue a single read and return whatever comes back — a short
        /// read would then silently deliver less than the caller asked for.
        ///
        /// - Returns: `nil` at EOF, otherwise the bytes actually read, which may be fewer than
        /// `length`. The offset advances by that same amount.
        func readData(length: UInt64) async throws -> Data? {
            guard length > .zero else {
                return nil
            }

            guard case .read(let readHandle) = handle else {
                return nil
            }

            return try await lock.withLock { () async throws -> Data? in
                var data = Data()
                var read = 0

                while read < Int(length) {
                    // Same reasoning as `writeData`: checked per retry, not only on entry.
                    try Task.checkCancellation()

                    let chunk = try await readHandle.readChunk(
                        fromAbsoluteOffset: Int64(_offset) + Int64(read),
                        length: .bytes(Int64(length) - Int64(read))
                    )

                    guard chunk.readableBytes > .zero else {
                        break
                    }

                    data.append(contentsOf: chunk.readableBytesView)
                    read += chunk.readableBytes
                }

                guard read > .zero else {
                    return nil
                }

                _offset += UInt64(read)
                return data
            }
        }

        /// - Note: Closing twice is a no op rather than an error. The storage detaches its
        /// streams before closing them, so this should not happen, and closing a handle that
        /// has already been closed is a far worse outcome than a redundant call.
        func close() async throws {
            try await lock.withLock {
                guard !_isClosed else {
                    return
                }

                _isClosed = true

                switch handle {
                case .read(let readHandle):
                    try await readHandle.close()
                case .write(let writeHandle):
                    try await writeHandle.close()
                }
            }
        }
    }
}
