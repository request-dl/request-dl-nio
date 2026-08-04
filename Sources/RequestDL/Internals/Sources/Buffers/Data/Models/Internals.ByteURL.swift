//
// See LICENSE for this package's licensing information.
//

import NIOCore
import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
// import protocol Foundation.DataProtocol
#endif

extension Internals {

    /// An in memory location, standing where a file URL would otherwise stand.
    ///
    /// Identity is the reference itself, not the bytes, which is what makes it usable as a URL:
    /// two handles opened against the same instance address the same store.
    final class ByteURL: @unchecked Sendable {

        // MARK: - Internal properties

        /// A copy of the current bytes.
        ///
        /// - Warning: Reading this hands out a second reference to the buffer's storage, so the
        /// next write has to copy it before it can mutate. Use ``withStorage(_:)`` for anything
        /// that touches the buffer rather than just inspecting it.
        var buffer: NIOCore.ByteBuffer {
            lock.withLock { _buffer }
        }

        /// High water mark of the writer index, which is the size of the store.
        ///
        /// Not the buffer's own `writerIndex`. A write in the middle rewinds that one, and the
        /// bytes past it are still there.
        var writtenBytes: Int {
            lock.withLock { _writtenBytes }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        // Deliberately not `lazy`. A lazy var is reached through a getter and a setter, so
        // `&_buffer` would become a read, a modify and a write, which is exactly what
        // ``withStorage(_:)`` exists to avoid.
        private var _buffer = NIOCore.ByteBuffer()
        private var _writtenBytes: Int = .zero

        // MARK: - Inits

        init() {}

        /// - Important: Only for a `ByteBuffer` that this instance will own exclusively from
        /// here on. The slice is taken, not copied.
        init(_ buffer: NIOCore.ByteBuffer) {
            let buffer = buffer.slice()
            self._buffer = buffer
            self._writtenBytes = buffer.readableBytes
        }

        // MARK: - Internal methods

        /// Reads and writes the bytes and the written count inside a single critical section.
        ///
        /// Two things depend on this rather than on the properties above.
        ///
        /// Atomicity: a seek followed by a read is one logical operation, and there are always
        /// two handles on the same `ByteURL`, one reading and one writing. Moving the indices
        /// through a computed property makes every line a separate critical section, and the
        /// two handles interleave between them.
        ///
        /// Cost: `ByteBuffer` is copy on write. Reading it out of a getter leaves the storage
        /// referenced twice, so every write copies everything written so far before appending.
        /// Mutating it in place through `inout` keeps the reference unique, which turns filling
        /// a buffer from quadratic back into linear.
        func withStorage<Result>(
            _ body: (inout NIOCore.ByteBuffer, inout Int) -> Result
        ) -> Result {
            lock.withLock {
                body(&_buffer, &_writtenBytes)
            }
        }

        /// Replaces the whole content.
        ///
        /// Unlike writing through a handle, this shortens the resource when the new content is
        /// smaller. A handle seeks and overwrites, and the written count only ever rises, so
        /// the tail of the previous content survives and keeps counting as written.
        func replace<Bytes: DataProtocol>(with data: Bytes) {
            withStorage { buffer, writtenBytes in
                buffer.clear()

                // `writeBytes`, not `writeData`. The latter comes from `NIOFoundationCompat`,
                // which imports the whole of `Foundation`.
                _ = buffer.writeBytes(data)

                writtenBytes = buffer.writerIndex
            }
        }
    }
}

// MARK: - Hashable

extension Internals.ByteURL: Hashable {

    static func == (_ lhs: Internals.ByteURL, _ rhs: Internals.ByteURL) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

// MARK: - Data extension

extension Data {

    /// Replaces the whole content of `url` with this data.
    ///
    /// - Note: Declared `throws` to mirror `Data.write(to:)` for a file URL. It does not
    /// currently fail.
    func write(to url: Internals.ByteURL) throws {
        url.replace(with: self)
    }
}
