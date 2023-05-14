/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    struct Buffer<Stream: StreamBuffer>: Sendable {

        private final class Storage: @unchecked Sendable {

            // MARK: - Internal properties

            var readerIndex: UInt64 {
                lock.withLock {
                    _storedInputStream?.offset ?? .zero
                }
            }

            var writerIndex: UInt64 {
                lock.withLock {
                    _storedOutputStream?.offset ?? .zero
                }
            }

            var writtenBytes: Int {
                lock.withLock {
                    url.writtenBytes
                }
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

            // MARK: - Internal methods

            func moveReaderIndex(to index: UInt64) throws {
                try lock.withLockVoid {
                    guard url.isResourceAvailable() else {
                        return
                    }

                    try _inputStream.seek(to: index)
                }
            }

            func readData(_ length: UInt64) -> Data? {
                try? lock.withLock {
                    try _readData(length)
                }
            }

            func readBytes(_ length: UInt64) -> [UInt8]? {
                try? lock.withLock {
                    guard let data = try _readData(length) else {
                        return nil
                    }

                    let count = data.count / MemoryLayout<UInt8>.size
                    var bytes = [UInt8](repeating: 0, count: count)
                    data.copyBytes(to: &bytes, count: count)

                    return bytes
                }
            }

            func moveWriterIndex(to index: UInt64) throws {
                try lock.withLockVoid {
                    guard url.isResourceAvailable() else {
                        return
                    }

                    try _outputStream.seek(to: index)
                }
            }

            func writeData<Data: DataProtocol>(_ data: Data) {
                try? lock.withLock {
                    url.createResourceIfNeeded()
                    try _outputStream.writeData(data)
                }
            }

            func writeBytes<Bytes: Sequence>(_ bytes: Bytes) where Bytes.Element == UInt8 {
                try? lock.withLock {
                    url.createResourceIfNeeded()
                    try _outputStream.writeData(Data(bytes))
                }
            }


            // MARK: - Unsafe methods

            private func _readData(_ length: UInt64) throws -> Data? {
                guard url.isResourceAvailable() else {
                    return nil
                }

                return try _inputStream.readData(length: length)
            }

            deinit {
                do {
                    try _storedInputStream?.close()
                    try _storedOutputStream?.close()
                } catch {
                    Internals.Log.failure(error)
                }
            }
        }

        // MARK: - Internal properties

        var readerIndex: Int {
            lock.withLock {
                _readerIndex
            }
        }

        var readableBytes: Int {
            lock.withLock {
                _readableBytes
            }
        }

        var writerIndex: Int {
            lock.withLock {
                _writerIndex
            }
        }

        var writableBytes: Int {
            lock.withLock {
                Int(storage.writtenBytes) - _writerIndex
            }
        }

        var estimatedBytes: Int {
            lock.withLock {
                Int(storage.writtenBytes)
            }
        }

        // MARK: - Private properties

        fileprivate let lock: Lock

        private let storage: Storage

        // MARK: - Unsafe properties

        fileprivate var _readableBytes: Int {
            _writerIndex - _readerIndex
        }

        fileprivate var _readerIndex: Int = .zero

        fileprivate var _writerIndex: Int

        // MARK: - Inits

        init(_ url: Foundation.URL) {
            if Stream.self is FileStreamBuffer.Type, let url = FileBufferURL(url) as? Stream.URL {
                self.init(storage: .init(url))
                return
            }

            self.init(Internals.Buffer<Internals.FileStreamBuffer>(url))
        }

        init(_ url: Internals.ByteURL) {
            if Stream.self is ByteStreamBuffer.Type, let url = ByteBufferURL(url) as? Stream.URL {
                self.init(storage: .init(url))
                return
            }

            self.init(Internals.Buffer<Internals.ByteStreamBuffer>(url))
        }

        init<Data: DataProtocol>(_ data: Data) {
            self.init()
            _writeData(data)
        }

        init<S>(_ bytes: S) where S: Sequence, S.Element == UInt8 {
            self.init()
            _writeBytes(bytes)
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
            self = buffer.lock.withLock {
                if let buffer = buffer as? Buffer<Stream> {
                    let storage = buffer.storage
                    var _self = Buffer(storage: storage)
                    _self._writerIndex = buffer._writerIndex
                    _self._readerIndex = buffer._readerIndex
                    return _self
                } else {
                    var buffer = buffer
                    let writerIndex = buffer._writerIndex
                    let readerIndex = buffer._readerIndex
                    buffer._moveReaderIndex(to: .zero)

                    var _self: Self

                    if let data = buffer._readData(buffer._readableBytes) {
                        _self = .init(data)
                    } else {
                        _self = .init()
                    }

                    _self._moveWriterIndex(to: writerIndex)
                    _self._moveReaderIndex(to: readerIndex)

                    return _self
                }
            }
        }

        private init(storage: Storage) {
            self.lock = .init()
            self.storage = storage
            self._writerIndex = storage.writtenBytes
        }

        // MARK: - Unsafe methods

        fileprivate mutating func _moveReaderIndex(to index: Int) {
            precondition(index <= _writerIndex)
            precondition(index >= .zero)
            _readerIndex = index
        }

        fileprivate mutating func _readData(_ length: Int) -> Data? {
            guard length >= .zero, _readerIndex + length <= _writerIndex else {
                return nil
            }

            do {
                try storage.moveReaderIndex(to: UInt64(_readerIndex))
                let data = storage.readData(UInt64(length))
                _readerIndex = Int(storage.readerIndex)
                return data
            } catch {
                return nil
            }
        }

        fileprivate mutating func _readBytes(_ length: Int) -> [UInt8]? {
            guard length >= .zero, _readerIndex + length <= _writerIndex else {
                return nil
            }

            do {
                try storage.moveReaderIndex(to: UInt64(_readerIndex))
                let data = storage.readBytes(UInt64(length))
                _readerIndex = Int(storage.readerIndex)
                return data
            } catch {
                return nil
            }
        }

        fileprivate mutating func _moveWriterIndex(to index: Int) {
            precondition(_readerIndex <= index)
            precondition(index >= .zero)
            _writerIndex = index
        }

        fileprivate mutating func _writeData<Data: DataProtocol>(_ data: Data) {
            do {
                try storage.moveWriterIndex(to: UInt64(_writerIndex))
                storage.writeData(data)
                _writerIndex = Int(storage.writerIndex)
            } catch {}
        }

        fileprivate mutating func _writeBytes<Bytes: Sequence>(_ bytes: Bytes) where Bytes.Element == UInt8 {
            do {
                try storage.moveWriterIndex(to: UInt64(_writerIndex))
                storage.writeBytes(bytes)
                _writerIndex = Int(storage.writerIndex)
            } catch {}
        }

        fileprivate mutating func _writeBuffer<OtherStream: StreamBuffer>(_ buffer: inout Buffer<OtherStream>) {
            if let data = buffer._readData(buffer._readableBytes) {
                _writeData(data)
            }
        }
    }
}

extension Internals.Buffer {

    // MARK: - Internal reading methods

    mutating func moveReaderIndex(to index: Int) {
        lock.withLock {
            _moveReaderIndex(to: index)
        }
    }

    mutating func readData(_ length: Int) -> Data? {
        lock.withLock {
            _readData(length)
        }
    }

    mutating func readBytes(_ length: Int) -> [UInt8]? {
        lock.withLock {
            _readBytes(length)
        }
    }

    func getData() -> Data? {
        lock.withLock {
            var mutableSelf = self
            return mutableSelf._readData(mutableSelf._readableBytes)
        }
    }

    func getBytes() -> [UInt8]? {
        lock.withLock {
            var mutableSelf = self
            return mutableSelf._readBytes(mutableSelf._readableBytes)
        }
    }

    func getData(at index: Int, length: Int) -> Data? {
        lock.withLock {
            var mutableSelf = self

            guard index + length <= mutableSelf._writerIndex else {
                return nil
            }

            mutableSelf._moveReaderIndex(to: index)
            return mutableSelf._readData(length)
        }
    }

    func getBytes(at index: Int, length: Int) -> [UInt8]? {
        lock.withLock {
            var mutableSelf = self

            guard index + length <= mutableSelf._writerIndex else {
                return nil
            }

            mutableSelf._moveReaderIndex(to: index)
            return mutableSelf._readBytes(length)
        }
    }
}

extension Internals.Buffer {

    // MARK: - Internal writing methods

    mutating func moveWriterIndex(to index: Int) {
        lock.withLock {
            _moveWriterIndex(to: index)
        }
    }

    mutating func writeData<Data: DataProtocol>(_ data: Data) {
        lock.withLock {
            _writeData(data)
        }
    }

    mutating func writeBytes<Bytes: Sequence>(_ bytes: Bytes) where Bytes.Element == UInt8 {
        lock.withLock {
            _writeBytes(bytes)
        }
    }

    mutating func writeBuffer<OtherStream: StreamBuffer>(_ buffer: inout Internals.Buffer<OtherStream>) {
        lock.withLock {
            buffer.lock.withLock {
                _writeBuffer(&buffer)
            }
        }
    }

    func setData<Data: DataProtocol>(_ data: Data) {
        lock.withLock {
            var mutableSelf = self
            mutableSelf._writeData(data)
        }
    }

    func setBytes<Bytes: Sequence>(_ bytes: Bytes) where Bytes.Element == UInt8 {
        lock.withLock {
            var mutableSelf = self
            mutableSelf._writeBytes(bytes)
        }
    }

    func setData<Data: DataProtocol>(_ data: Data, at index: Int) {
        lock.withLock {
            var mutableSelf = self
            mutableSelf._moveWriterIndex(to: index)
            mutableSelf._writeData(data)
        }
    }

    func setBytes<Bytes: Sequence>(_ bytes: Bytes, at index: Int) where Bytes.Element == UInt8 {
        lock.withLock {
            var mutableSelf = self
            mutableSelf._moveWriterIndex(to: index)
            mutableSelf._writeBytes(bytes)
        }
    }
}
