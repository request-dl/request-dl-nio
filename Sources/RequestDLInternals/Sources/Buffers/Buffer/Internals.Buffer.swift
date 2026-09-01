//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.Data
import protocol Foundation.DataProtocol
#endif

extension Internals {

    /// A cursor over a shared byte store.
    ///
    /// ## Ownership model
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
    ///
    /// ## Cursors can outlive the bytes they point at
    ///
    /// Because the store is shared and the cursors are not, one copy calling ``clear()`` leaves
    /// every other copy holding indices past the end of an empty store. Reads in that state
    /// answer `nil` rather than trapping, and writes land past the end, leaving a zero filled
    /// gap behind them, which is what a file handle does when it seeks past EOF. Treat cursors
    /// taken from a buffer somebody else may reset as advisory.
    ///
    /// ## Concurrency
    ///
    /// Every mutating member is `async`, so it needs exclusive access to `self` held across a
    /// suspension. That is fine for a local `var` and illegal for a stored property of a class
    /// or an actor: `await someActor.buffer.readData(8)` does not compile. Callers that keep a
    /// buffer as a stored property have to move it into a local first and write it back after,
    /// or hold it behind a type that owns the serialization itself.
    package struct Buffer<Stream: StreamBuffer>: Sendable {

        /// The shared byte store, plus the streams currently open over it.
        ///
        /// One instance is shared by every copy of the surrounding buffer, which is what makes
        /// the bytes reference semantics. All access is serialized here, one whole logical
        /// operation at a time, rather than one property at a time.
        private final class Storage: @unchecked Sendable {

            // MARK: - Internal properties

            /// Bytes currently in the resource.
            ///
            /// - Important: On a file system this is a stat call. It deliberately does not
            /// take the lock: `url` is immutable and reports either through its own
            /// synchronization or through the file system, so guarding it here would only
            /// queue size checks behind whatever read or write is in flight.
            package var writtenBytes: Int {
                get async {
                    await url.writtenBytes
                }
            }

            // MARK: - Private static properties

            /// Flags a read/write/close/clear that is still running after 15s. Development
            /// builds only — see `AsyncLock.Watchdog`.
            ///
            /// - Note: Computed rather than a stored `static let` — `Storage` is nested inside
            /// the generic `Buffer<Stream>`, and Swift does not allow stored static properties
            /// in a generic type.
            private static var watchdog: AsyncLock.Watchdog? {
                #if DEBUG
                .init(seconds: 15) { Internals.assertionFailure($0) }
                #else
                nil
                #endif
            }

            // MARK: - Private properties

            private let lock = AsyncLock(watchdog: watchdog)
            private let url: Stream.URL

            // MARK: - Unsafe properties

            /// - Warning: Lockless. Only reachable from inside `lock`, or from `deinit`.
            private var _inputStream: Stream {
                get async throws {
                    if let stream = _storedInputStream {
                        return stream
                    }

                    let stream = try await Stream(readingFrom: url)
                    _storedInputStream = stream
                    return stream
                }
            }

            /// - Warning: Lockless. Only reachable from inside `lock`, or from `deinit`.
            private var _outputStream: Stream {
                get async throws {
                    if let stream = _storedOutputStream {
                        return stream
                    }

                    let stream = try await Stream(writingTo: url)
                    _storedOutputStream = stream
                    return stream
                }
            }

            private var _storedInputStream: Stream?
            private var _storedOutputStream: Stream?

            /// Whether this storage has already established that its resource exists, either
            /// by creating it or by a prior stat succeeding.
            private var _hasConfirmedResource = false

            // MARK: - Inits

            package init(_ url: Stream.URL) {
                self.url = url
            }

            deinit {
                // `deinit` cannot suspend, so tear down is handed to a detached task. Every
                // value it needs is copied out first: capturing `self` here would resurrect an
                // object that is already being destroyed.
                //
                // The consequence is that a temporary file is removed asynchronously. A
                // process that exits immediately after dropping its last buffer can leave the
                // file behind. Call `close()` and `clear()` explicitly when that matters.
                let streams = _detachStreams()
                let url = self.url

                Task.detached {
                    try? await streams.input?.close()
                    try? await streams.output?.close()
                    await url.removeIfTemporary()
                }
            }

            // MARK: - Internal methods

            /// Seeks and reads as one operation.
            ///
            /// Seeking and reading through separate calls means separate critical sections, and
            /// a second cursor over the same storage can move the stream in between. The caller
            /// then reads from wherever the other one left it.
            ///
            /// - Returns: The data, and the offset the reader ended at. A failed or refused
            /// read reports `nil` and the offset it was handed, so the caller's cursor stays
            /// where it was.
            package func read(at index: UInt64, length: UInt64) async -> (data: Data?, offset: UInt64) {
                await lock.withLock { () async -> (data: Data?, offset: UInt64) in
                    guard await _isResourceAvailable() else {
                        return (nil, index)
                    }

                    do {
                        let stream = try await _inputStream

                        try await stream.seek(to: index)

                        let data = try await stream.readData(length: length)
                        let offset = try await stream.offset

                        return (data, offset)
                    } catch {
                        return (nil, index)
                    }
                }
            }

            /// Seeks and writes as one operation.
            ///
            /// - Returns: The offset the writer ended at, or `index` when the write failed.
            /// Failure is silent by design, matching every other operation here, so a caller
            /// that needs to know detects it by the offset not having moved.
            package func write<Bytes: DataProtocol & Sendable>(at index: UInt64, data: Bytes) async -> UInt64 {
                await lock.withLock { () async -> UInt64 in
                    await _createResourceIfNeeded()

                    do {
                        let stream = try await _outputStream

                        try await stream.seek(to: index)
                        try await stream.writeData(data)

                        return try await stream.offset
                    } catch {
                        return index
                    }
                }
            }

            /// Releases the open streams. The next operation reopens what it needs.
            ///
            /// Streams are cached because every operation seeks absolutely, so reopening is
            /// only a syscall away from correct. Caching costs a file descriptor for as long
            /// as anything holds this storage, which for a disk cache means one per entry the
            /// caller keeps alive.
            ///
            /// Both streams are closed even when the first one fails, and the first error is
            /// the one reported.
            package func close() async throws {
                let streams = await lock.withLock { _detachStreams() }

                var failure: Error?

                do {
                    try await streams.input?.close()
                } catch {
                    failure = error
                }

                do {
                    try await streams.output?.close()
                } catch {
                    failure = failure ?? error
                }

                if let failure {
                    throw failure
                }
            }

            /// Drops every byte, letting the resource shrink back.
            ///
            /// The cached streams are closed first. Truncating is allowed to replace the
            /// backing resource rather than shorten it in place, and a descriptor opened
            /// against the old one would keep reading and writing an object nobody else can
            /// reach.
            package func clear() async {
                await lock.withLock {
                    let streams = _detachStreams()

                    try? await streams.input?.close()
                    try? await streams.output?.close()

                    await url.truncate()
                    _hasConfirmedResource = false
                }
            }

            // MARK: - Unsafe methods

            /// - Warning: Lockless. Only reachable from inside `lock`, or from `deinit`.
            ///
            /// Hands the cached streams over to the caller and forgets them, so closing can
            /// happen outside the critical section without another operation reaching a stream
            /// that is halfway shut. Anything arriving afterwards opens its own.
            private func _detachStreams() -> (input: Stream?, output: Stream?) {
                defer {
                    _storedInputStream = nil
                    _storedOutputStream = nil
                }

                return (_storedInputStream, _storedOutputStream)
            }

            /// - Warning: Lockless. Only reachable from inside `lock`.
            ///
            /// Creation is attempted once per storage rather than once per write, which took a
            /// stat and sometimes an open and a close on every single call. A resource deleted
            /// underneath a live storage is not recovered from, which is the same answer the
            /// cached descriptors already give.
            private func _createResourceIfNeeded() async {
                guard !_hasConfirmedResource else {
                    return
                }

                await url.createResourceIfNeeded()
                _hasConfirmedResource = true
            }

            /// - Warning: Lockless. Only reachable from inside `lock`.
            ///
            /// `url.isResourceAvailable()` is a file system stat, and under heavy concurrent
            /// reads on sandboxed Apple simulators it intermittently reports a file as missing
            /// in short, contiguous windows, with nothing thrown and no descriptor ever closed
            /// underneath this storage. Retrying that stat a
            /// handful of times narrows the window but does not close it: the same simulator
            /// contention that produces one flaky answer can produce five in a row once enough
            /// callers are stat-ing the same path at once, which is exactly what happens once
            /// hundreds of reads land on one storage concurrently.
            ///
            /// The reliable fix is not a bigger retry budget, it is not re-asking a question
            /// this storage already knows the answer to. Once this instance has itself created
            /// the resource, or a stat has ever come back positive, nothing other than
            /// ``clear()`` can make it disappear from underneath it — same invariant
            /// `_createResourceIfNeeded()` already relies on. So the confirmation is cached and
            /// every read after the first reachable one skips the stat entirely, which is also
            /// what removes it from that concurrent contention going forward.
            private func _isResourceAvailable() async -> Bool {
                guard !_hasConfirmedResource else {
                    return true
                }

                let attempts = 5
                let retryDelay: UInt64 = 2_000_000

                for attempt in 0..<attempts {
                    if await url.isResourceAvailable() {
                        _hasConfirmedResource = true
                        return true
                    }

                    if attempt + 1 < attempts {
                        try? await Task.sleep(nanoseconds: retryDelay)
                    }
                }

                return false
            }
        }

        // MARK: - Internal properties

        /// Bytes between this cursor's reader and writer indices.
        package var readableBytes: Int {
            _writerIndex - _readerIndex
        }

        package var readerIndex: Int {
            _readerIndex
        }

        package var writerIndex: Int {
            _writerIndex
        }

        /// Bytes already in the store that sit past this cursor's writer index, and would
        /// therefore be overwritten by the next write.
        ///
        /// Not remaining capacity. These buffers grow on demand, so there is no ceiling to
        /// report, and the previous name `writableBytes` promised the opposite of what the
        /// number means to anyone arriving from `NIOCore.ByteBuffer`.
        package var overwritableBytes: Int {
            get async {
                await storage.writtenBytes - _writerIndex
            }
        }

        /// Bytes currently in the shared store, regardless of where this cursor sits.
        ///
        /// - Important: Reads through to the resource, so it is I/O on the file backed variant.
        package var estimatedBytes: Int {
            get async {
                await storage.writtenBytes
            }
        }

        // MARK: - Private properties

        private let storage: Storage

        private var _readerIndex: Int = .zero
        private var _writerIndex: Int

        // MARK: - Inits

        /// Addresses a file system location.
        ///
        /// When `Stream` cannot address one, the bytes are read through a file backed buffer
        /// and copied into this one, which means the whole file lands in memory.
        package init(_ url: URL) async {
            // Asking the storage type what it can address, instead of testing `Stream.self`
            // against a concrete type at runtime.
            if let url = Stream.URL.make(from: url) {
                await self.init(storage: .init(url))
                return
            }

            await self.init(Internals.Buffer<Internals.FileStreamBuffer>(url))
        }

        /// Addresses an in memory location.
        ///
        /// When `Stream` cannot address one, the bytes are copied in, as above.
        package init(_ url: Internals.ByteURL) async {
            if let url = Stream.URL.make(from: url) {
                await self.init(storage: .init(url))
                return
            }

            await self.init(Internals.Buffer<Internals.ByteStreamBuffer>(url))
        }

        package init<Bytes: DataProtocol & Sendable>(_ data: Bytes) async {
            await self.init()
            await writeData(data)
        }

        package init<Bytes: Sequence & Sendable>(_ bytes: Bytes) async where Bytes.Element == UInt8 {
            await self.init()
            await writeBytes(bytes)
        }

        package init(_ string: String) async {
            await self.init(Data(string.utf8))
        }

        package init(_ staticString: StaticString) async {
            // The bytes are copied out before the suspension. `UnsafeBufferPointer` is not
            // `Sendable`, so it cannot be handed to an `async` initializer directly.
            let data = staticString.withUTF8Buffer { Data($0) }
            await self.init(data)
        }

        /// Opens an empty buffer over a fresh temporary resource.
        package init() async {
            await self.init(storage: .init(.temporaryURL))
        }

        /// Copies `buffer`.
        ///
        /// Same stream type: the bytes are shared and only the cursors are copied, so this is
        /// cheap and the two buffers stay linked. Different stream type: the bytes are carried
        /// across into a new store, so the two are independent from then on.
        package init<OtherStream: StreamBuffer>(_ buffer: Buffer<OtherStream>) async {
            if let buffer = buffer as? Buffer<Stream> {
                await self.init(storage: buffer.storage)
                _readerIndex = buffer._readerIndex
                _writerIndex = buffer._writerIndex
                return
            }

            // `source` is a copy, so rewinding it does not disturb the caller's cursors.
            var source = buffer
            let readerIndex = source._readerIndex
            let writerIndex = source._writerIndex

            source.moveReaderIndex(to: .zero)

            let length = source.readableBytes

            guard length > .zero, let data = await source.readData(length) else {
                await self.init()
                return
            }

            await self.init(data)

            // Clamped rather than restored outright. A short read leaves fewer bytes here than
            // the source reported, and pointing the cursors at the original indices would put
            // them past the end of what actually arrived.
            moveWriterIndex(to: min(writerIndex, _writerIndex))
            moveReaderIndex(to: min(readerIndex, _writerIndex))
        }

        /// Addresses `url` directly, bypassing `Stream.URL.make(from:)`.
        ///
        /// Every other constructor above starts from a `Foundation.URL`/`Internals.ByteURL` and
        /// asks `Stream.URL.make(from:)` — a `static` factory with no channel to carry anything
        /// beyond the address itself — to produce the concrete `Stream.URL`. That is a problem
        /// for a `Stream.URL` that also needs per-instance context, such as
        /// `Internals.EncryptedFileBufferURL`'s encryption key: there is no way to smuggle a key
        /// through `make(from:)` without embedding it in the `Foundation.URL` itself, which must
        /// never happen. This exists for exactly that case — a caller that already has a fully
        /// formed `Stream.URL` in hand skips `make(from:)` entirely.
        package init(addressing url: Stream.URL) async {
            await self.init(storage: .init(url))
        }

        private init(storage: Storage) async {
            self.init(storage: storage, writerIndex: await storage.writtenBytes)
        }

        private init(storage: Storage, writerIndex: Int) {
            self.storage = storage
            self._writerIndex = writerIndex
        }
    }
}

// MARK: - Synchronous construction, in memory only

extension Internals.Buffer where Stream == Internals.ByteStreamBuffer {

    /// Opens a buffer over an in memory store, without suspending.
    ///
    /// ## Why this can be synchronous when the general initializer cannot
    ///
    /// The only asynchronous step in `init(_ url:)` is reading the initial writer index, and
    /// following that call down for an in memory store gives:
    ///
    /// ```
    /// Buffer.init(_:) async
    ///   -> Storage.writtenBytes          get async
    ///   -> ByteBufferURL.writtenBytes    get async   <- async purely to satisfy `BufferURL`
    ///   -> ByteURL.writtenBytes                      <- a lock read, no suspension at all
    /// ```
    ///
    /// `BufferURL.writtenBytes` is `async` because the file backed conformance has to stat.
    /// The in memory one never suspends, so the `async` on this path is ceremony, and it was
    /// blocking three call sites that genuinely cannot await: a NIO delegate callback, a
    /// `didSet`, and the body of a synchronous lock.
    ///
    /// ## Overloading with the asynchronous initializer
    ///
    /// This shadows `init(_ url: Internals.ByteURL) async` by effect only. Swift resolves that
    /// the way it resolves any `async` overload: an asynchronous context picks the `async` one,
    /// so every existing `await Internals.DataBuffer(url)` still means what it always did, and
    /// a synchronous context picks this one because it is the only candidate. Nothing has to
    /// change at the call sites that already worked.
    ///
    /// Only the `ByteURL` initializer is mirrored. `init()` and the `DataProtocol` ones could
    /// be too, but nothing needs them, and every added overload is one more place for
    /// resolution to surprise somebody.
    ///
    /// - Important: In `Internals.ClientResponseReceiver` this is not merely convenient, it is
    /// required. Response chunks are handed to a queue that preserves submission order, and
    /// submission is synchronous. Building the buffer in a detached task instead would let two
    /// chunks race to enqueue, and the body would be reassembled out of order.
    package init(_ url: Internals.ByteURL) {
        self.init(
            storage: .init(Internals.ByteBufferURL(url)),
            writerIndex: url.writtenBytes
        )
    }

}

// MARK: - Reading

extension Internals.Buffer {

    /// - Precondition: `index` is within `0...writerIndex`. Moving a cursor to an index that
    /// does not exist is a programming error, unlike querying one, which reports.
    package mutating func moveReaderIndex(to index: Int) {
        precondition(index >= .zero, "Reader index \(index) is negative")
        precondition(index <= _writerIndex, "Reader index \(index) is past the writer index \(_writerIndex)")
        _readerIndex = index
    }

    /// Reads forward from the reader index and advances it by however much arrived.
    ///
    /// - Returns: `nil` when the range is not readable, when the store no longer holds it, or
    /// when the underlying resource failed. The reader index does not move in any of those
    /// cases. A short read advances the cursor by the bytes actually delivered, not by
    /// `length`.
    package mutating func readData(_ length: Int) async -> Data? {
        // Subtracting rather than adding, so a large `length` cannot overflow past the check.
        guard length >= .zero, length <= _writerIndex - _readerIndex else {
            return nil
        }

        let result = await storage.read(at: UInt64(_readerIndex), length: UInt64(length))
        _readerIndex = Int(result.offset)
        return result.data
    }

    /// - Note: Same semantics as ``readData(_:)``.
    package mutating func readBytes(_ length: Int) async -> [UInt8]? {
        await readData(length).map { [UInt8]($0) }
    }

    /// Reads the whole readable range without moving this cursor.
    package func getData() async -> Data? {
        await getData(at: _readerIndex, length: readableBytes)
    }

    /// Reads the whole readable range without moving this cursor.
    package func getBytes() async -> [UInt8]? {
        await getBytes(at: _readerIndex, length: readableBytes)
    }

    /// Reads a range without moving this cursor.
    ///
    /// Goes straight to the store at an absolute index, so it neither reads nor writes this
    /// cursor. Out of range reports rather than traps: moving a cursor to a bad index is a
    /// programming error and keeps its `precondition`, but asking a query for a range that is
    /// not there is an ordinary answer of "nothing".
    package func getData(at index: Int, length: Int) async -> Data? {
        guard isValidRange(at: index, length: length) else {
            return nil
        }

        return await storage.read(at: UInt64(index), length: UInt64(length)).data
    }

    /// Reads a range without moving this cursor.
    /// - Note: Same out of range behaviour as ``getData(at:length:)``.
    package func getBytes(at index: Int, length: Int) async -> [UInt8]? {
        await getData(at: index, length: length).map { [UInt8]($0) }
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

    /// - Precondition: `index` is within `readerIndex...`. Rewinding the writer behind the
    /// reader would make `readableBytes` negative.
    package mutating func moveWriterIndex(to index: Int) {
        precondition(index >= .zero, "Writer index \(index) is negative")
        precondition(index >= _readerIndex, "Writer index \(index) is behind the reader index \(_readerIndex)")
        _writerIndex = index
    }

    /// Writes at the writer index and advances it.
    ///
    /// - Important: A failed write is silent, as it is everywhere else in this type. The writer
    /// index stays put, so the bytes are lost rather than half applied.
    package mutating func writeData<Bytes: DataProtocol & Sendable>(_ data: Bytes) async {
        _writerIndex = Int(await storage.write(at: UInt64(_writerIndex), data: data))
    }

    /// - Note: Same semantics as ``writeData(_:)``.
    package mutating func writeBytes<Bytes: Sequence & Sendable>(_ bytes: Bytes) async where Bytes.Element == UInt8 {
        await writeData(Data(bytes))
    }

    /// Drains `buffer` into this one.
    ///
    /// - Important: Must not take a lock on either side. Both cursors are local to their own
    /// copy, and the two storage operations are each atomic on their own, so there is nothing
    /// left to hold across the pair. Locking both buffers in argument order deadlocks outright
    /// when the two are copies of each other — copies share one lock object, the lock is not
    /// reentrant, and two threads calling this in opposite directions deadlock each other.
    package mutating func writeBuffer<OtherStream: StreamBuffer>(_ buffer: inout Internals.Buffer<OtherStream>) async {
        let length = buffer.readableBytes

        guard length > .zero, let data = await buffer.readData(length) else {
            return
        }

        await writeData(data)
    }

    /// Drops every byte and rewinds both cursors.
    ///
    /// Moving the cursors alone leaves the store at whatever size it grew to, because the
    /// written count is a high water mark that only rises. This lets that memory go.
    ///
    /// - Warning: The store is shared. Other copies keep their own cursors, which now point
    /// past the end of an empty resource.
    package mutating func clear() async {
        await storage.clear()
        _readerIndex = .zero
        _writerIndex = .zero
    }

    /// Releases the open streams without discarding anything.
    ///
    /// Worth calling once a buffer has been read and is going to be kept around, since the
    /// cached stream is a file descriptor on the disk backed variant. The next operation
    /// reopens whatever it needs.
    package func close() async throws {
        try await storage.close()
    }

    /// Overwrites bytes already in the buffer, leaving this cursor where it was.
    ///
    /// The useful case is `index < writerIndex`: the bytes land inside the readable range and
    /// can be read straight back, which is what patching a placeholder needs.
    ///
    /// - Warning: Writing at or past the writer index puts the bytes outside this cursor's
    /// readable range, and the next `writeData` starts at that same index and overwrites them.
    /// Follow with ``moveWriterIndex(to:)`` when that is the intent.
    ///
    /// - Throws: ``Internals/BufferIndexError`` when `index` is negative.
    package func setData<Bytes: DataProtocol & Sendable>(_ data: Bytes, at index: Int) async throws {
        guard index >= .zero else {
            throw Internals.BufferIndexError(index: index)
        }

        // Straight to the store rather than through a mutable copy of `self`. Routing it
        // through `moveWriterIndex` tripped that method's precondition whenever `index` sat
        // behind the reader, which is precisely the patching case this exists for.
        _ = await storage.write(at: UInt64(index), data: data)
    }

    /// Overwrites bytes already in the buffer, leaving this cursor where it was.
    /// - Warning: Same caveat as ``setData(_:at:)``.
    /// - Precondition: `index` is not negative.
    package func setBytes<Bytes: Sequence & Sendable>(_ bytes: Bytes, at index: Int) async
    where Bytes.Element == UInt8 {
        precondition(index >= .zero, "Buffer index \(index) is negative")
        _ = await storage.write(at: UInt64(index), data: Data(bytes))
    }
}

// MARK: - Errors

extension Internals {

    package struct BufferIndexError: Error, CustomStringConvertible {

        package let index: Int

        package var description: String {
            "Attempted to address a buffer at the negative index \(index)"
        }
    }
}
