/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    struct DataBuffer: BufferProtocol {

        private let storage: Storage

        private(set) var readerIndex: Int = .zero

        private(set) var writerIndex: Int

        private init(storage: Storage) {
            self.storage = storage
            self.writerIndex = storage.writtenBytes
        }
    }
}

extension Internals.DataBuffer {

    init(_ url: URL) {
        self.init(Internals.FileBuffer(url))
    }

    init(_ url: Internals.ByteURL) {
        self.init(storage: .init(url))
    }

    init<Data: DataProtocol>(_ data: Data) {
        self.init()
        writeData(data)
    }

    init<S>(_ bytes: S) where S: Sequence, S.Element == UInt8 {
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
        self.init(Internals.ByteURL())
    }

    init<Buffer: BufferProtocol>(_ buffer: Buffer) {
        if let fileBuffer = buffer as? Internals.DataBuffer {
            let storage = fileBuffer.storage
            self.init(storage: storage)
            self.writerIndex = buffer.writerIndex
            self.readerIndex = buffer.readerIndex
        } else {
            var buffer = buffer
            let writerIndex = buffer.writerIndex
            let readerIndex = buffer.readerIndex
            buffer.moveReaderIndex(to: .zero)

            if let data = buffer.readData(buffer.readableBytes) {
                self.init(data)
            } else {
                self.init()
            }

            moveWriterIndex(to: writerIndex)
            moveReaderIndex(to: readerIndex)
        }
    }
}

extension Internals.DataBuffer {

    var readableBytes: Int {
        writerIndex - readerIndex
    }

    var writableBytes: Int {
        storage.writtenBytes - writerIndex
    }

    var estimatedBytes: Int {
        storage.writtenBytes
    }

    mutating func moveReaderIndex(to index: Int) {
        precondition(index <= writerIndex)
        precondition(index >= .zero)
        readerIndex = index
    }

    mutating func moveWriterIndex(to index: Int) {
        precondition(readerIndex <= index)
        precondition(index >= .zero)
        writerIndex = index
    }
}

extension Internals.DataBuffer {

    mutating func writeData<Data: DataProtocol>(_ data: Data) {
        do {
            try storage.moveWriterIndex(to: writerIndex)
            storage.writeData(data)
            writerIndex = storage.writerIndex
        } catch {}
    }

    mutating func writeBytes<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
        do {
            try storage.moveWriterIndex(to: writerIndex)
            storage.writeBytes(bytes)
            writerIndex = storage.writerIndex
        } catch {}
    }

    mutating func writeBuffer<Buffer: BufferProtocol>(_ buffer: inout Buffer) {
        if let data = buffer.readData(buffer.readableBytes) {
            writeData(data)
        }
    }
}

extension Internals.DataBuffer {

    mutating func readData(_ length: Int) -> Data? {
        guard length >= .zero, readerIndex + length <= writerIndex else {
            return nil
        }

        do {
            try storage.moveReaderIndex(to: readerIndex)
            let data = storage.readData(length)
            readerIndex = storage.readerIndex
            return data
        } catch {
            return nil
        }
    }

    mutating func readBytes(_ length: Int) -> [UInt8]? {
        guard length >= .zero, readerIndex + length <= writerIndex else {
            return nil
        }

        do {
            try storage.moveReaderIndex(to: readerIndex)
            let data = storage.readBytes(length)
            readerIndex = storage.readerIndex
            return data
        } catch {
            return nil
        }
    }
}

extension Internals.DataBuffer {

    fileprivate final class Storage: @unchecked Sendable {

        // MARK: - Internal properties

        var writerIndex: Int {
            lock.withLock {
                (try? _storedOutputStream?.offset()).map(Int.init) ?? .zero
            }
        }

        var readerIndex: Int {
            lock.withLock {
                (try? _storedInputStream?.offset()).map(Int.init) ?? .zero
            }
        }

        var writtenBytes: Int {
            lock.withLock {
                url.writtenBytes
            }
        }

        // MARK: - Private properties

        private let lock = Lock()
        private let url: Internals.ByteURL

        // MARK: - Unsafe properties

        private var _storedInputStream: Internals.ByteHandle?
        private var _storedOutputStream: Internals.ByteHandle?

        private var _inputStream: Internals.ByteHandle {
            get throws {
                if let stream = _storedInputStream {
                    return stream
                }

                let stream = Internals.ByteHandle(forReadingFrom: url)
                _storedInputStream = stream
                return stream
            }
        }

        private var _outputStream: Internals.ByteHandle {
            get throws {
                if let stream = _storedOutputStream {
                    return stream
                }

                let stream = Internals.ByteHandle(forWritingTo: url)
                _storedOutputStream = stream
                return stream
            }
        }

        // MARK: - Inits

        init(_ url: Internals.ByteURL) {
            self.url = url
        }

        // MARK: - Internals methods

        func writeData<Data: DataProtocol>(_ data: Data) {
            lock.withLockVoid {
                try? _outputStream.write(contentsOf: data)
            }
        }

        func writeBytes<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
            lock.withLockVoid {
                try? _outputStream.write(contentsOf: Data(bytes))
            }
        }

        func readData(_ length: Int) -> Data? {
            lock.withLock {
                _readData(length)
            }
        }

        func readBytes(_ length: Int) -> [UInt8]? {
            lock.withLock {
                guard let data = _readData(length) else {
                    return nil
                }

                let count = data.count / MemoryLayout<UInt8>.size
                var bytes = [UInt8](repeating: 0, count: count)
                data.copyBytes(to: &bytes, count: count)

                return bytes
            }
        }

        func moveReaderIndex(to index: Int) throws {
            try lock.withLockVoid {
                try _inputStream.seek(toOffset: UInt64(index))
            }
        }

        func moveWriterIndex(to index: Int) throws {
            try lock.withLockVoid {
                try _outputStream.seek(toOffset: UInt64(index))
            }
        }

        // MARK: - Unsafe methods

        private func _readData(_ length: Int) -> Data? {
            try? _inputStream.read(upToCount: length)
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
}
