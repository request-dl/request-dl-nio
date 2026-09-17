//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import protocol Foundation.DataProtocol
#endif

#if canImport(NIOCore)
import NIOCore
import NIOFoundationEssentialsCompat
#endif

extension Internals {

    /// A byte store shaped like `NIOCore.ByteBuffer` (reader/writer cursors over a growable
    /// buffer) without callers ever knowing what actually backs it.
    ///
    /// Backed by `Data` by default. When built from an existing `NIOCore.ByteBuffer` (only
    /// possible where NIO is available), it stays `ByteBuffer`-backed instead of converting
    /// eagerly, so a value that started as one never pays a conversion unless something asks
    /// for the other representation, and once it does, the result is cached back into
    /// ``storage``, so asking again does not pay a second time.
    ///
    /// This is the currency at the handful of places that need one shape both executors can
    /// agree on (request body chunks, the compression stream protocols, `ByteURL`'s own
    /// storage). Whatever is `.nio`-only keeps using `NIOCore.ByteBuffer` directly: this type
    /// only exists at the boundary between the two.
    package struct Bytes: Sendable {

        /// Mirrors `NIOCore.ByteBuffer.ByteTransferStrategy` without requiring NIO to name it.
        /// See ``asData(byteTransferStrategy:)``.
        package enum ByteTransferStrategy: Sendable {
            case copy
            case noCopy
            case automatic
        }

        // MARK: - Private storage

        private struct DataStorage: Sendable {
            /// Every byte ever written, including any past the current `writerIndex` left
            /// behind by a rewind (the same "bytes past it are still there" invariant
            /// `NIOCore.ByteBuffer` has). Always addressed `0..<data.count`.
            var data: Data
            var readerIndex: Int
            var writerIndex: Int
        }

        private enum Storage: Sendable {
            case data(DataStorage)
            #if canImport(NIOCore)
            case byteBuffer(NIOCore.ByteBuffer)
            #endif
        }

        private var storage: Storage

        /// Runs `body` with exclusive access to the `.data` case's payload, `nil` if `storage`
        /// isn't `.data`-backed.
        ///
        /// `storage` is overwritten with an empty placeholder *before* `body` runs, dropping its
        /// reference to the old `DataStorage` so `body`'s own copy is the only one left. Skipping
        /// that step (matching `case .data(var dataStorage):` and mutating `dataStorage` in place
        /// with `storage` still holding the original) leaves both alive for the duration of the
        /// call: `Data` sees itself referenced twice, so every `append`/`replaceSubrange` copies
        /// everything written so far before it can mutate, turning what looks like an amortized
        /// O(1) write into an O(n) one and a build-up of writes into O(n²). This is the same
        /// discipline `Internals.ByteURL.withStorage(_:)` relies on to keep repeated writes to a
        /// single instance linear, extended one level down so it isn't undone by aliasing this
        /// type introduces internally.
        private mutating func withDataStorage<Result>(_ body: (inout DataStorage) -> Result) -> Result? {
            guard case .data(var dataStorage) = storage else {
                return nil
            }

            storage = .data(DataStorage(data: Data(), readerIndex: .zero, writerIndex: .zero))

            defer { storage = .data(dataStorage) }
            return body(&dataStorage)
        }

        // MARK: - Inits

        package init() {
            storage = .data(DataStorage(data: Data(), readerIndex: .zero, writerIndex: .zero))
        }

        package init(_ data: Data) {
            storage = .data(DataStorage(data: data, readerIndex: data.startIndex, writerIndex: data.endIndex))
        }

        /// - Note: Matches `NIOCore.ByteBuffer(repeating:count:)`: the result has `count` bytes
        /// already written, not an empty buffer with `count` bytes of spare capacity.
        package init(repeating byte: UInt8, count: Int) {
            self.init()
            writeRepeatingByte(byte, count: count)
        }

        #if canImport(NIOCore)
        /// Adopts `buffer` as is. Stays `ByteBuffer`-backed: nothing is converted until a
        /// caller explicitly asks for ``asData(byteTransferStrategy:)``.
        package init(_ buffer: NIOCore.ByteBuffer) {
            storage = .byteBuffer(buffer)
        }
        #endif

        private init(storage: Storage) {
            self.storage = storage
        }

        // MARK: - Internal properties

        package var readerIndex: Int {
            switch storage {
            case .data(let dataStorage):
                return dataStorage.readerIndex
            #if canImport(NIOCore)
            case .byteBuffer(let buffer):
                return buffer.readerIndex
            #endif
            }
        }

        package var writerIndex: Int {
            switch storage {
            case .data(let dataStorage):
                return dataStorage.writerIndex
            #if canImport(NIOCore)
            case .byteBuffer(let buffer):
                return buffer.writerIndex
            #endif
            }
        }

        package var readableBytes: Int {
            writerIndex - readerIndex
        }

        // MARK: - Internal methods

        package mutating func moveReaderIndex(to index: Int) {
            precondition(index >= .zero, "Reader index \(index) is negative")
            precondition(index <= writerIndex, "Reader index \(index) is past the writer index \(writerIndex)")

            switch storage {
            case .data(var dataStorage):
                dataStorage.readerIndex = index
                storage = .data(dataStorage)
            #if canImport(NIOCore)
            case .byteBuffer(var buffer):
                buffer.moveReaderIndex(to: index)
                storage = .byteBuffer(buffer)
            #endif
            }
        }

        /// Mirrors `NIOCore.ByteBuffer.moveWriterIndex(to:)`: moving forward exposes whatever
        /// this store's backing already holds there rather than clearing it first.
        ///
        /// For the `.data` case that is either real bytes still physically present from an
        /// earlier, larger write that was since rewound (reused as is, matching what NIO's own
        /// capacity reuse would do), or genuinely new ground, which is zero-filled because
        /// growing `Data` has nothing else to reveal. For the `.byteBuffer` case this defers to
        /// NIO outright, capacity precondition included: a caller that wants a deterministic
        /// zero-filled gap regardless of backing (the way a file handle seeking past EOF
        /// behaves) should call ``writeRepeatingByte(_:count:)`` instead, exactly as
        /// `Internals.ByteHandle.write(contentsOf:)` already does.
        package mutating func moveWriterIndex(to index: Int) {
            precondition(index >= .zero, "Writer index \(index) is negative")
            precondition(index >= readerIndex, "Writer index \(index) is behind the reader index \(readerIndex)")

            switch storage {
            case .data:
                withDataStorage { dataStorage in
                    if index > dataStorage.data.count {
                        dataStorage.data.append(
                            contentsOf: repeatElement(UInt8.zero, count: index - dataStorage.data.count)
                        )
                    }
                    dataStorage.writerIndex = index
                }
            #if canImport(NIOCore)
            case .byteBuffer(var buffer):
                buffer.moveWriterIndex(to: index)
                storage = .byteBuffer(buffer)
            #endif
            }
        }

        package mutating func clear() {
            switch storage {
            case .data:
                withDataStorage { dataStorage in
                    dataStorage.data.removeAll(keepingCapacity: true)
                    dataStorage.readerIndex = .zero
                    dataStorage.writerIndex = .zero
                }
            #if canImport(NIOCore)
            case .byteBuffer(var buffer):
                buffer.clear()
                storage = .byteBuffer(buffer)
            #endif
            }
        }

        /// Writes at the writer index and advances it, overwriting existing bytes in place
        /// rather than truncating whatever was already past the new writer index.
        @discardableResult
        package mutating func writeBytes<Bytes: DataProtocol>(_ bytes: Bytes) -> Int {
            _write(bytes)
        }

        /// - Note: Same semantics as ``writeBytes(_:)``.
        @discardableResult
        package mutating func writeRepeatingByte(_ byte: UInt8, count: Int) -> Int {
            _write(repeatElement(byte, count: count))
        }

        @discardableResult
        private mutating func _write<Bytes: Collection>(_ bytes: Bytes) -> Int where Bytes.Element == UInt8 {
            let count = bytes.count

            switch storage {
            case .data:
                withDataStorage { dataStorage in
                    let overlapEnd = Swift.min(dataStorage.writerIndex + count, dataStorage.data.count)
                    let overlapLength = Swift.max(.zero, overlapEnd - dataStorage.writerIndex)

                    if overlapLength > .zero {
                        let range = dataStorage.writerIndex..<(dataStorage.writerIndex + overlapLength)
                        dataStorage.data.replaceSubrange(range, with: bytes.prefix(overlapLength))
                    }

                    if count > overlapLength {
                        dataStorage.data.append(contentsOf: bytes.dropFirst(overlapLength))
                    }

                    dataStorage.writerIndex += count
                }
                return count
            #if canImport(NIOCore)
            case .byteBuffer(var buffer):
                let written = buffer.writeBytes(bytes)
                storage = .byteBuffer(buffer)
                return written
            #endif
            }
        }

        /// Reads `length` bytes from the reader index, advancing it, and returns them as a new
        /// ``Bytes``: `nil` when fewer than `length` bytes are readable.
        package mutating func readSlice(length: Int) -> Self? {
            guard length >= .zero, length <= readableBytes else {
                return nil
            }

            switch storage {
            case .data(var dataStorage):
                let range = dataStorage.readerIndex..<(dataStorage.readerIndex + length)
                let slice = Data(dataStorage.data[range])
                dataStorage.readerIndex += length
                storage = .data(dataStorage)
                return Self(storage: .data(DataStorage(data: slice, readerIndex: .zero, writerIndex: slice.count)))
            #if canImport(NIOCore)
            case .byteBuffer(var buffer):
                guard let slice = buffer.readSlice(length: length) else {
                    return nil
                }
                storage = .byteBuffer(buffer)
                return Self(storage: .byteBuffer(slice))
            #endif
            }
        }

        /// The readable range as a new, independent ``Bytes`` starting at index `0`. Does not
        /// move this cursor.
        package func slice() -> Self {
            switch storage {
            case .data(let dataStorage):
                let range = dataStorage.readerIndex..<dataStorage.writerIndex
                let slice = Data(dataStorage.data[range])
                return Self(storage: .data(DataStorage(data: slice, readerIndex: .zero, writerIndex: slice.count)))
            #if canImport(NIOCore)
            case .byteBuffer(let buffer):
                return Self(storage: .byteBuffer(buffer.slice()))
            #endif
            }
        }

        /// The readable range as `Data`, without moving this cursor.
        ///
        /// - Important: When this is `ByteBuffer`-backed, the result is cached back into
        /// `self`: asking again does not convert a second time, but a caller that only ever
        /// needed `Data` once has now paid to keep both representations reachable. A `ByteBuffer`
        /// caller is expected to prefer ``asByteBuffer()`` if this value is likely to cross the
        /// boundary more than once.
        @discardableResult
        package mutating func asData(byteTransferStrategy: ByteTransferStrategy = .automatic) -> Data {
            switch storage {
            case .data(let dataStorage):
                return Data(dataStorage.data[dataStorage.readerIndex..<dataStorage.writerIndex])
            #if canImport(NIOCore)
            case .byteBuffer(let buffer):
                let strategy: NIOCore.ByteBuffer.ByteTransferStrategy
                switch byteTransferStrategy {
                case .copy:
                    strategy = .copy
                case .noCopy:
                    strategy = .noCopy
                case .automatic:
                    strategy = .automatic
                }

                let data =
                    buffer.getData(
                        at: buffer.readerIndex,
                        length: buffer.readableBytes,
                        byteTransferStrategy: strategy
                    ) ?? Data()

                storage = .data(DataStorage(data: data, readerIndex: .zero, writerIndex: data.count))
                return data
            #endif
            }
        }

        /// Appends the readable range straight into `data`, without moving this cursor or
        /// materializing a standalone ``Bytes``-owned `Data` first.
        ///
        /// Prefer this over `data.append(contentsOf: asData())` when accumulating several chunks
        /// into one growing buffer: `asData()` pays to materialize (and, for the `.byteBuffer`
        /// case, cache) an intermediate `Data` before `append` can copy from it, paying the copy
        /// twice. This copies once, straight from whichever storage backs this value into
        /// `data`'s own storage — matching what appending `NIOCore.ByteBuffer.readableBytesView`
        /// directly used to cost before this type existed.
        package func append(to data: inout Data) {
            switch storage {
            case .data(let dataStorage):
                data.append(dataStorage.data[dataStorage.readerIndex..<dataStorage.writerIndex])
            #if canImport(NIOCore)
            case .byteBuffer(let buffer):
                data.append(contentsOf: buffer.readableBytesView)
            #endif
            }
        }

        /// The readable range as `[UInt8]`, without moving this cursor or materializing a
        /// standalone `Data` first.
        ///
        /// Prefer this over `Array(asData())` for a caller that only needs `[UInt8]` once (e.g.
        /// handing bytes to a `[UInt8]`-based API like `RequestDL.Compressor`): `asData()` pays
        /// to materialize (and, for the `.byteBuffer` case, cache) an intermediate `Data` before
        /// `Array(_:)` can copy from it, paying the copy twice. This copies once, straight from
        /// whichever storage backs this value.
        package func asBytes() -> [UInt8] {
            switch storage {
            case .data(let dataStorage):
                return Array(dataStorage.data[dataStorage.readerIndex..<dataStorage.writerIndex])
            #if canImport(NIOCore)
            case .byteBuffer(let buffer):
                return Array(buffer.readableBytesView)
            #endif
            }
        }

        #if canImport(NIOCore)
        /// The readable range as a `NIOCore.ByteBuffer`, without moving this cursor.
        ///
        /// - Important: Same caching caveat as ``asData(byteTransferStrategy:)``, in reverse.
        @discardableResult
        package mutating func asByteBuffer() -> NIOCore.ByteBuffer {
            switch storage {
            case .byteBuffer(let buffer):
                return buffer
            case .data(let dataStorage):
                var buffer = NIOCore.ByteBuffer()
                buffer.writeBytes(dataStorage.data[dataStorage.readerIndex..<dataStorage.writerIndex])
                storage = .byteBuffer(buffer)
                return buffer
            }
        }
        #endif
    }
}
