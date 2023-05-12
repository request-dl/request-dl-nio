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

    fileprivate class Storage {

        private let url: Internals.ByteURL

        private var _inputStream: Internals.ByteHandle?
        private var _outputStream: Internals.ByteHandle?

        var writerIndex: Int {
            (try? _outputStream?.offset()).map(Int.init) ?? .zero
        }

        var readerIndex: Int {
            return (try? _inputStream?.offset()).map(Int.init) ?? .zero
        }

        var writtenBytes: Int {
            url.writtenBytes
        }

        var inputStream: Internals.ByteHandle {
            get throws {
                if let stream = _inputStream {
                    return stream
                }

                let stream = Internals.ByteHandle(forReadingFrom: url)
                _inputStream = stream
                return stream
            }
        }

        var outputStream: Internals.ByteHandle {
            get throws {
                if let stream = _outputStream {
                    return stream
                }

                let stream = Internals.ByteHandle(forWritingTo: url)
                _outputStream = stream
                return stream
            }
        }

        init(_ url: Internals.ByteURL) {
            self.url = url
        }

        func writeData<Data: DataProtocol>(_ data: Data) {
            try? outputStream.write(contentsOf: data)
        }

        func writeBytes<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
            try? outputStream.write(contentsOf: Data(bytes))
        }

        func readData(_ length: Int) -> Data? {
            (try? inputStream.read(upToCount: length))
        }

        func readBytes(_ length: Int) -> [UInt8]? {
            guard let data = readData(length) else {
                return nil
            }

            let count = data.count / MemoryLayout<UInt8>.size
            var bytes = [UInt8](repeating: 0, count: count)
            data.copyBytes(to: &bytes, count: count)

            return bytes
        }

        func moveReaderIndex(to index: Int) throws {
            try inputStream.seek(toOffset: UInt64(index))
        }

        func moveWriterIndex(to index: Int) throws {
            try outputStream.seek(toOffset: UInt64(index))
        }

        deinit {
            do {
                try _inputStream?.close()
                try _outputStream?.close()
            } catch {
                Internals.Log.failure(error)
            }
        }
    }
}
