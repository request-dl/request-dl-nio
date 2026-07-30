/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import SwiftAsyncStream

extension Internals {

    /// A cursor over a shared byte store.
    ///
    /// The cursors are value semantics, one pair per copy of this struct. The bytes behind them
    /// are reference semantics, shared by every copy taken from the same source. That split is
    /// the whole design, and it is why this type carries no lock of its own: there is nothing
    /// here for one to protect. Two threads holding separate copies cannot collide over the
    /// cursors, and two threads sharing one copy are already an exclusivity violation that no
    /// lock would fix.
    ///
    /// What is genuinely shared lives in ``Storage``, which is synchronized there, one whole
    /// operation at a time.
    struct Buffer<Stream: StreamBuffer>: Sendable {

        private final class Storage: @unchecked Sendable {

            // MARK: - Internal properties

            /// - Important: On a file system this is a stat call. It deliberately does not
            /// take the lock: `url` is immutable and reports either through its own
            /// synchronization or through the file system, so guarding it here would only
            /// queue size checks behind whatever read or write is in flight.
            var writtenBytes: Int {
                url.writtenBytes
            }

            // MARK: - Private properties

            private let lock = Lock()
            private let url: Stream.URL

            // MARK: - Unsafe properties

            private var _inputStream: Stream {
                get throws {
                    if let stream = _storedInputStream {
                        return stream
                    }

                    let stream = try Stream(readingFrom: url)
                    _storedInputStream = stream
                    return stream
                }
            }

            private var _outputStream: Stream {
                get throws {
                    if let stream = _storedOutputStream {
                        return stream
                    }

                    let stream = try Stream(writingTo: url)
                    _storedOutputStream = stream
                    return stream
                }
            }

            private var _storedInputStream: Stream?
            private var _storedOutputStream: Stream?

            // MARK: - Inits

            init(_ url: Stream.URL) {
                self.url = url
            }

            deinit {
                _close()
                url.removeIfTemporary()
            }

            // MARK: - Internal methods

            /// Seeks and reads as one operation.
            ///
            /// Seeking and reading through separate calls means separate critical sections, and
            /// a second cursor over the same storage can move the stream in between. The caller
            /// then reads from wherever the other one left it.
            ///
            /// - Returns: The data, and the offset the reader ended at.
            func read(at index: UInt64, length: UInt64) -> (data: Data?, offset: UInt64) {
                lock.withLock { () -> (data: Data?, offset: UInt64) in
                    guard url.isResourceAvailable() else {
                        return (nil, index)
                    }

                    do {
                        let stream = try _inputStream

                        try stream.seek(to: index)
                        let data = try stream.readData(length: length)

                        return (data, stream.offset)
                    } catch {
                        return (nil, index)
                    }
                }
            }

            /// Releases the open streams. The next operation reopens what it needs.
            ///
            /// Streams are cached because every operation seeks absolutely, so reopening is
            /// only a syscall away from correct. Caching costs a file descriptor for as long
            /// as anything holds this storage, which for a disk cache means one per entry the
            /// caller keeps alive.
            func close() {
                lock.withLock { _close() }
            }

            /// Drops every byte, letting the resource shrink back.
            func clear() {
                lock.withLock { url.truncate() }
            }

            /// Seeks and writes as one operation.
            /// - Returns: The offset the writer ended at.
            func write<Bytes: DataProtocol>(at index: UInt64, data: Bytes) -> UInt64 {
                lock.withLock { () -> UInt64 in
                    url.createResourceIfNeeded()

                    do {
                        let stream = try _outputStream

                        try stream.seek(to: index)
                        try stream.writeData(data)

                        return stream.offset
                    } catch {
                        return index
                    }
                }
            }

            // MARK: - Unsafe methods

            /// - Warning: Lockless, except from `deinit` where nothing else can reach this.
            ///
            /// Closed independently, and never fatally. A temporary file can disappear
            /// underneath us, and taking the process down from a deinit over that is not a
            /// reasonable trade. Chaining them also meant a failure on the first one leaked
            /// the second.
            private func _close() {
                try? _storedInputStream?.close()
                try? _storedOutputStream?.close()

                _storedInputStream = nil
                _storedOutputStream = nil
            }
        }

        // MARK: - Internal properties

        var readableBytes: Int {
            _writerIndex - _readerIndex
        }

        var readerIndex: Int {
            _readerIndex
        }

        var writerIndex: Int {
            _writerIndex
        }

        /// Bytes already in the store that sit past this cursor's writer index, and would
        /// therefore be overwritten by the next write.
        ///
        /// Not remaining capacity. These buffers grow on demand, so there is no ceiling to
        /// report, and the previous name `writableBytes` promised the opposite of what the
        /// number means to anyone arriving from `NIOCore.ByteBuffer`.
        var overwritableBytes: Int {
            storage.writtenBytes - _writerIndex
        }

        var estimatedBytes: Int {
            storage.writtenBytes
        }

        // MARK: - Private properties

        private let storage: Storage

        private var _readerIndex: Int = .zero
        private var _writerIndex: Int

        // MARK: - Inits

        init(_ url: Foundation.URL) {
            // Asking the storage type what it can address, instead of testing `Stream.self`
            // against a concrete type at runtime.
            if let url = Stream.URL.make(from: url) {
                self.init(storage: .init(url))
                return
            }

            self.init(Internals.Buffer<Internals.FileStreamBuffer>(url))
        }

        init(_ url: Internals.ByteURL) {
            if let url = Stream.URL.make(from: url) {
                self.init(storage: .init(url))
                return
            }

            self.init(Internals.Buffer<Internals.ByteStreamBuffer>(url))
        }

        init<Bytes: DataProtocol>(_ data: Bytes) {
            self.init()
            writeData(data)
        }

        init<Bytes: Sequence>(_ bytes: Bytes) where Bytes.Element == UInt8 {
            self.init()
            writeBytes(bytes)
        }

        init(_ string: String) {
            self.init(Data(string.utf8))
        }

        init(_ staticString: StaticString) {
            self.init(UnsafeBufferPointer(
                start: staticString.utf8Start,
                count: staticString.utf8CodeUnitCount
            ))
        }

        init() {
            self.init(storage: .init(.temporaryURL))
        }

        init<OtherStream: StreamBuffer>(_ buffer: Buffer<OtherStream>) {
            if let buffer = buffer as? Buffer<Stream> {
                // Same stream type: share the bytes, copy the cursors.
                self.init(storage: buffer.storage)
                _writerIndex = buffer._writerIndex
                _readerIndex = buffer._readerIndex
                return
            }

            // Different stream type: the bytes have to be carried across. `source` is a copy,
            // so rewinding it does not disturb the caller's cursors.
            var source = buffer
            let writerIndex = source._writerIndex
            let readerIndex = source._readerIndex

            source.moveReaderIndex(to: .zero)

            if let data = source.readData(source.readableBytes) {
                self.init(data)
            } else {
                self.init()
            }

            moveWriterIndex(to: writerIndex)
            moveReaderIndex(to: readerIndex)
        }

        private init(storage: Storage) {
            self.storage = storage
            self._writerIndex = storage.writtenBytes
        }
    }
}

// MARK: - Reading

extension Internals.Buffer {

    mutating func moveReaderIndex(to index: Int) {
        precondition(index <= _writerIndex)
        precondition(index >= .zero)
        _readerIndex = index
    }

    mutating func readData(_ length: Int) -> Data? {
        guard length >= .zero, _readerIndex + length <= _writerIndex else {
            return nil
        }

        let result = storage.read(at: UInt64(_readerIndex), length: UInt64(length))
        _readerIndex = Int(result.offset)
        return result.data
    }

    mutating func readBytes(_ length: Int) -> [UInt8]? {
        readData(length).map { [UInt8]($0) }
    }

    /// Reads the whole readable range without moving this cursor.
    ///
    /// The read still seeks the shared stream, so this is not free of effect on the store, only
    /// free of effect on the caller. That is harmless because every storage operation positions
    /// itself absolutely before reading, so nobody inherits the position this leaves behind.
    func getData() -> Data? {
        var mutableSelf = self
        return mutableSelf.readData(mutableSelf.readableBytes)
    }

    /// Reads the whole readable range without moving this cursor.
    func getBytes() -> [UInt8]? {
        var mutableSelf = self
        return mutableSelf.readBytes(mutableSelf.readableBytes)
    }

    /// Reads a range without moving this cursor.
    ///
    /// Out of range reports rather than traps. Moving a cursor to a bad index is a programming
    /// error and keeps its `precondition`, but asking a query for a range that is not there is
    /// an ordinary answer of "nothing".
    func getData(at index: Int, length: Int) -> Data? {
        guard isValidRange(at: index, length: length) else {
            return nil
        }

        var mutableSelf = self
        mutableSelf.moveReaderIndex(to: index)
        return mutableSelf.readData(length)
    }

    /// Reads a range without moving this cursor.
    /// - Note: Same out of range behaviour as ``getData(at:length:)``.
    func getBytes(at index: Int, length: Int) -> [UInt8]? {
        guard isValidRange(at: index, length: length) else {
            return nil
        }

        var mutableSelf = self
        mutableSelf.moveReaderIndex(to: index)
        return mutableSelf.readBytes(length)
    }

    /// - Note: Subtracts rather than adds, so a large `index` cannot overflow its way past the
    /// check.
    private func isValidRange(at index: Int, length: Int) -> Bool {
        index >= .zero
            && length >= .zero
            && index <= _writerIndex
            && length <= _writerIndex - index
    }
}

// MARK: - Writing

extension Internals.Buffer {

    mutating func moveWriterIndex(to index: Int) {
        precondition(_readerIndex <= index)
        precondition(index >= .zero)
        _writerIndex = index
    }

    mutating func writeData<Bytes: DataProtocol>(_ data: Bytes) {
        _writerIndex = Int(storage.write(at: UInt64(_writerIndex), data: data))
    }

    mutating func writeBytes<Bytes: Sequence>(_ bytes: Bytes) where Bytes.Element == UInt8 {
        writeData(Data(bytes))
    }

    /// Drains `buffer` into this one.
    ///
    /// No longer takes a lock on either side. Both cursors are local to their own copy, and the
    /// two storage operations are each atomic on their own, so there is nothing left to hold
    /// across the pair. The previous version locked both buffers in argument order, which
    /// deadlocked outright when the two were copies of each other, since copies share one lock
    /// object and the lock is not reentrant, and deadlocked between two threads calling it in
    /// opposite directions.
    mutating func writeBuffer<OtherStream: StreamBuffer>(_ buffer: inout Internals.Buffer<OtherStream>) {
        guard let data = buffer.readData(buffer.readableBytes) else {
            return
        }

        writeData(data)
    }

    /// Drops every byte and rewinds both cursors.
    ///
    /// Moving the cursors alone leaves the store at whatever size it grew to, because the
    /// written count is a high water mark that only rises. This lets that memory go.
    mutating func clear() {
        storage.clear()
        _readerIndex = .zero
        _writerIndex = .zero
    }

    /// Releases the open streams without discarding anything.
    ///
    /// Worth calling once a buffer has been read and is going to be kept around, since the
    /// cached stream is a file descriptor on the disk backed variant.
    func close() {
        storage.close()
    }

    /// Overwrites bytes already in the buffer, leaving this cursor where it was.
    ///
    /// The useful case is `index < writerIndex`: the bytes land inside the readable range and
    /// can be read straight back, which is what patching a placeholder needs.
    ///
    /// - Warning: Writing at or past the writer index puts the bytes outside this cursor's
    /// readable range, and the next `writeData` starts at that same index and overwrites them.
    /// Follow with ``moveWriterIndex(to:)`` when that is the intent.
    func setData<Bytes: DataProtocol>(_ data: Bytes, at index: Int) {
        var mutableSelf = self
        mutableSelf.moveWriterIndex(to: index)
        mutableSelf.writeData(data)
    }

    /// Overwrites bytes already in the buffer, leaving this cursor where it was.
    /// - Warning: Same caveat as ``setData(_:at:)``.
    func setBytes<Bytes: Sequence>(_ bytes: Bytes, at index: Int) where Bytes.Element == UInt8 {
        var mutableSelf = self
        mutableSelf.moveWriterIndex(to: index)
        mutableSelf.writeBytes(bytes)
    }
}
