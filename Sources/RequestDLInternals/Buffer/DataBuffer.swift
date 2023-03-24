/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct DataBuffer: BufferProtocol {

    private let storage: Storage

    public private(set) var readerIndex: Int = .zero

    public private(set) var writerIndex: Int

    private init(storage: Storage) {
        self.storage = storage
        self.writerIndex = storage.writtenBytes
    }

    public init(_ url: URL) {
        self.init(FileBuffer(url))
    }

    public init(_ url: ByteURL) {
        self.init(storage: .init(url))
    }

    public init<Data: DataProtocol>(_ data: Data) {
        self.init()
        writeData(data)
    }

    public init<S>(_ bytes: S) where S: Sequence, S.Element == UInt8 {
        self.init()
        writeBytes(bytes)
    }

    public init(_ string: String) {
        self.init(Data(string.utf8))
    }

    public init(_ staticString: StaticString) {
        self.init(UnsafeBufferPointer(
            start: staticString.utf8Start,
            count: staticString.utf8CodeUnitCount
        ))
    }

    public init() {
        self.init(ByteURL())
    }

    public init<Buffer: BufferProtocol>(_ buffer: Buffer) {
        if let fileBuffer = buffer as? DataBuffer {
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

    public var readableBytes: Int {
        writerIndex - readerIndex
    }

    public var writableBytes: Int {
        storage.writtenBytes - writerIndex
    }

    public var estimatedBytes: Int {
        storage.writtenBytes
    }

    public mutating func writeData<Data: DataProtocol>(_ data: Data) {
        do {
            try storage.moveWriterIndex(to: writerIndex)
            storage.writeData(data)
            writerIndex = storage.writerIndex
        } catch {}
    }

    public mutating func writeBytes<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
        do {
            try storage.moveWriterIndex(to: writerIndex)
            storage.writeBytes(bytes)
            writerIndex = storage.writerIndex
        } catch {}
    }

    public mutating func readData(_ length: Int) -> Data? {
        precondition(length >= .zero)
        precondition(readerIndex + length <= writerIndex)

        do {
            try storage.moveReaderIndex(to: readerIndex)
            let data = storage.readData(length)
            readerIndex = storage.readerIndex
            return data
        } catch {
            return nil
        }
    }

    public mutating func readBytes(_ length: Int) -> [UInt8]? {
        precondition(length >= .zero)
        precondition(readerIndex + length <= writerIndex)

        do {
            try storage.moveReaderIndex(to: readerIndex)
            let data = storage.readBytes(length)
            readerIndex = storage.readerIndex
            return data
        } catch {
            return nil
        }
    }

    public mutating func moveReaderIndex(to index: Int) {
        precondition(index <= writerIndex)
        precondition(index >= .zero)
        readerIndex = index
    }

    public mutating func moveWriterIndex(to index: Int) {
        precondition(readerIndex <= index)
        precondition(index >= .zero)
        writerIndex = index
    }

    public mutating func writeBuffer<Buffer: BufferProtocol>(_ buffer: inout Buffer) {
        if let data = buffer.readData(buffer.readableBytes) {
            writeData(data)
        }
    }
}

extension DataBuffer {

    fileprivate class Storage {

        private let url: ByteURL

        private var _inputStream: ByteHandle?
        private var _outputStream: ByteHandle?

        var writerIndex: Int {
            (try? _outputStream?.offset()).map(Int.init) ?? .zero
        }

        var readerIndex: Int {
            return (try? _inputStream?.offset()).map(Int.init) ?? .zero
        }

        var writtenBytes: Int {
            url.writtenBytes
        }

        var inputStream: ByteHandle {
            get throws {
                if let stream = _inputStream {
                    return stream
                }

                let stream = ByteHandle(forReadingFrom: url)
                _inputStream = stream
                return stream
            }
        }

        var outputStream: ByteHandle {
            get throws {
                if let stream = _outputStream {
                    return stream
                }

                let stream = ByteHandle(forWritingTo: url)
                _outputStream = stream
                return stream
            }
        }

        init(_ url: ByteURL) {
            self.url = url
        }

        public func writeData<Data: DataProtocol>(_ data: Data) {
            try? outputStream.write(contentsOf: data)
        }

        public func writeBytes<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
            try? outputStream.write(contentsOf: Data(bytes))
        }

        public func readData(_ length: Int) -> Data? {
            (try? inputStream.read(upToCount: length))
        }

        public func readBytes(_ length: Int) -> [UInt8]? {
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
                fatalError("\(error)")
            }
        }
    }
}
