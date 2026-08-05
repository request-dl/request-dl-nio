//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import SystemPackage

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import protocol Foundation.DataProtocol
#endif

extension Internals {

    /// A stream over a file, backed by a single descriptor.
    ///
    /// ## Positioning
    ///
    /// Every syscall here addresses an absolute offset, `pread` and `pwrite` rather than
    /// `lseek` plus `read`. The offset this type reports is bookkeeping for the protocol, not
    /// state the kernel shares, so nothing else can move the file position underneath an
    /// operation in flight. That also drops the `Darwin` and `Glibc` imports the previous
    /// version needed for `lseek` and `errno`, which is the point of the exercise.
    ///
    /// ## Blocking
    ///
    /// `SystemPackage.FileDescriptor` is synchronous. These methods are `async` to satisfy
    /// ``StreamBuffer``, but the syscall runs on whichever cooperative thread called it. That
    /// is acceptable for the small, local reads this package performs and is not acceptable for
    /// large files. See the review notes for the `NIOFileSystem` handle alternative, which
    /// offloads to an I/O thread pool.
    final class FileStreamBuffer: @unchecked Sendable, StreamBuffer {

        typealias URL = Internals.FileBufferURL

        // MARK: - Internal properties

        var offset: UInt64 {
            get async throws {
                await lock.withLock { _offset }
            }
        }

        // MARK: - Private properties

        private let lock = AsyncLock()
        private let descriptor: SystemPackage.FileDescriptor

        // MARK: - Unsafe properties

        private var _offset: UInt64 = .zero
        private var _isClosed = false

        // MARK: - Inits

        /// - Throws: `Errno.noSuchFileOrDirectory` when the file is not there. Callers are
        /// expected to check availability first and treat the throw as an empty read.
        init(readingFrom url: URL) async throws {
            descriptor = try SystemPackage.FileDescriptor.open(url.path, .readOnly)
        }

        /// Opens for writing, creating the file when it does not exist.
        ///
        /// - Important: Must not pass `.truncate` — that would empty the file every time the
        /// storage lazily opens its output stream, so the first write to an existing file would
        /// destroy it and then leave a zero filled gap where the old content had been.
        init(writingTo url: URL) async throws {
            descriptor = try SystemPackage.FileDescriptor.open(
                url.path,
                .writeOnly,
                options: [.create],
                permissions: .ownerReadWrite
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

            try await lock.withLock {
                var written = 0

                while written < bytes.count {
                    let count = try bytes.withUnsafeBytes { pointer -> Int in
                        let remaining = UnsafeRawBufferPointer(rebasing: pointer[written...])

                        return try descriptor.write(
                            toAbsoluteOffset: Int64(_offset) + Int64(written),
                            remaining
                        )
                    }

                    // A zero length write with a non empty buffer is not progress, and looping
                    // on it spins forever.
                    guard count > .zero else {
                        throw Errno.ioError
                    }

                    written += count
                }

                _offset += UInt64(written)
            }
        }

        /// Reads up to `length` bytes, looping over short reads until EOF.
        ///
        /// - Important: Must not issue a single `read` and return whatever comes back — a short
        /// read would then silently deliver less than the caller asked for.
        ///
        /// - Returns: `nil` at EOF, otherwise the bytes actually read, which may be fewer than
        /// `length`. The offset advances by that same amount.
        func readData(length: UInt64) async throws -> Data? {
            guard length > .zero else {
                return nil
            }

            return try await lock.withLock { () throws -> Data? in
                var bytes = [UInt8](repeating: .zero, count: Int(length))
                var read = 0

                while read < bytes.count {
                    let count = try bytes.withUnsafeMutableBytes { pointer -> Int in
                        let remaining = UnsafeMutableRawBufferPointer(rebasing: pointer[read...])

                        return try descriptor.read(
                            fromAbsoluteOffset: Int64(_offset) + Int64(read),
                            into: remaining
                        )
                    }

                    guard count > .zero else {
                        break
                    }

                    read += count
                }

                guard read > .zero else {
                    return nil
                }

                _offset += UInt64(read)
                return Data(bytes.prefix(read))
            }
        }

        /// - Note: Closing twice is a no op rather than an error. The storage detaches its
        /// streams before closing them, so this should not happen, and taking a descriptor
        /// number that has since been reused is a far worse outcome than a redundant call.
        func close() async throws {
            try await lock.withLock {
                guard !_isClosed else {
                    return
                }

                _isClosed = true
                try descriptor.close()
            }
        }
    }
}
