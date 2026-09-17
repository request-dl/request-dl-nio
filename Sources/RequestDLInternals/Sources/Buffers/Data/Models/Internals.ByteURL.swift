//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import protocol Foundation.DataProtocol
#endif

#if canImport(NIOCore)
import NIOCore
#endif

extension Internals {

    /// An in memory location, standing where a file URL would otherwise stand.
    ///
    /// Identity is the reference itself, not the bytes, which is what makes it usable as a URL:
    /// two handles opened against the same instance address the same store.
    package final class ByteURL: @unchecked Sendable {

        // MARK: - Internal properties

        /// A copy of the current bytes.
        ///
        /// - Warning: Reading this hands out a second reference to the store's storage, so the
        /// next write has to copy it before it can mutate. Use ``withStorage(_:)`` for anything
        /// that touches the buffer rather than just inspecting it.
        package var bytes: Internals.Bytes {
            lock.withLock { _bytes }
        }

        /// High water mark of the writer index, which is the size of the store.
        ///
        /// Not the buffer's own `writerIndex`. A write in the middle rewinds that one, and the
        /// bytes past it are still there.
        package var writtenBytes: Int {
            lock.withLock { _writtenBytes }
        }

        // MARK: - Private properties

        private let lock = Lock()

        // MARK: - Unsafe properties

        // Deliberately not `lazy`. A lazy var is reached through a getter and a setter, so
        // `&_bytes` would become a read, a modify and a write, which is exactly what
        // ``withStorage(_:)`` exists to avoid.
        private var _bytes = Internals.Bytes()
        private var _writtenBytes: Int = .zero

        // MARK: - Inits

        package init() {}

        #if canImport(NIOCore)
        /// - Important: Only for a `ByteBuffer` that this instance will own exclusively from
        /// here on. The slice is taken, not copied.
        package init(_ buffer: NIOCore.ByteBuffer) {
            let bytes = Internals.Bytes(buffer).slice()
            self._bytes = bytes
            self._writtenBytes = bytes.readableBytes
        }
        #endif

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
        /// Cost: the store is copy on write. Reading it out of a getter leaves the storage
        /// referenced twice, so every write copies everything written so far before appending.
        /// Mutating it in place through `inout` keeps the reference unique, which turns filling
        /// a buffer from quadratic back into linear.
        package func withStorage<Result>(
            _ body: (inout Internals.Bytes, inout Int) -> Result
        ) -> Result {
            lock.withLock {
                body(&_bytes, &_writtenBytes)
            }
        }

        /// Replaces the whole content.
        ///
        /// Unlike writing through a handle, this shortens the resource when the new content is
        /// smaller. A handle seeks and overwrites, and the written count only ever rises, so
        /// the tail of the previous content survives and keeps counting as written.
        package func replace<Bytes: DataProtocol>(with data: Bytes) {
            withStorage { bytes, writtenBytes in
                bytes.clear()
                bytes.writeBytes(data)
                writtenBytes = bytes.writerIndex
            }
        }

        /// Same contract as ``replace(with:)`` above, for a caller that already holds an
        /// ``Internals/Bytes`` chunk (a `RequestBody`'s internal, `Data`-agnostic sequence, say):
        /// adopts its readable range directly as the new store instead of writing through
        /// `DataProtocol`, which for a `Data`-backed chunk would force a redundant copy on top
        /// of this store's own, and for a `ByteBuffer`-backed one would first force a `Data`
        /// materialization that has nothing to do with what this store actually needs.
        package func replace(with bytes: Internals.Bytes) {
            withStorage { storage, writtenBytes in
                storage = bytes.slice()
                writtenBytes = storage.writerIndex
            }
        }
    }
}

// MARK: - Hashable

extension Internals.ByteURL: Hashable {

    package static func == (_ lhs: Internals.ByteURL, _ rhs: Internals.ByteURL) -> Bool {
        lhs === rhs
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

// MARK: - Data extension

extension Data {

    /// Replaces the whole content of `url` with this data.
    ///
    /// - Note: Declared `throws` to mirror `Data.write(to:)` for a file URL. It does not
    /// currently fail.
    package func write(to url: Internals.ByteURL) throws {
        url.replace(with: self)
    }
}
