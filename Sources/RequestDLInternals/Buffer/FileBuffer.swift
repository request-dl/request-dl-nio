/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct FileBuffer: BufferProtocol {

    private let storage: Storage

    public private(set) var readerIndex: Int = .zero

    public private(set) var writerIndex: Int

    private init(storage: Storage) {
        self.storage = storage
        self.writerIndex = storage.writtenBytes
    }

    public init(_ url: URL) {
        self.init(storage: .init(url))
    }

    public init(_ url: ByteURL) {
        self.init(DataBuffer(url))
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
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RequestDL.FileBuffer.\(UUID()).temp")
        self.init(url)
    }

    public init<Buffer: BufferProtocol>(_ buffer: Buffer) {
        if let fileBuffer = buffer as? FileBuffer {
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

extension FileBuffer {

    fileprivate class Storage {

        private let url: URL

        private var _inputStream: FileHandle?
        private var _outputStream: FileHandle?

        var writerIndex: Int {
            if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
                return (try? _outputStream?.offset()).map(Int.init) ?? .zero
            } else {
                return (_outputStream?.offsetInFile).map(Int.init) ?? .zero
            }
        }

        var readerIndex: Int {
            if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
                return (try? _inputStream?.offset()).map(Int.init) ?? .zero
            } else {
                return (_inputStream?.offsetInFile).map(Int.init) ?? .zero
            }
        }

        private var path: String {
            url.absolutePath(percentEncoded: false)
        }

        var writtenBytes: Int {
            (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int ?? .zero
        }

        var inputStream: FileHandle {
            get throws {
                if let stream = _inputStream {
                    return stream
                }

                let stream = try FileHandle(forReadingFrom: url)
                _inputStream = stream
                return stream
            }
        }

        var outputStream: FileHandle {
            get throws {
                if let stream = _outputStream {
                    return stream
                }

                let stream = try FileHandle(forWritingTo: url)
                _outputStream = stream
                return stream
            }
        }

        private lazy var fileExists: Bool = {
            FileManager.default.fileExists(atPath: path)
        }()

        func createFileIfNeeded() {
            guard !fileExists else {
                return
            }

            fileExists = FileManager.default.createFile(atPath: path, contents: nil)
        }

        init(_ url: URL) {
            self.url = url
        }

        public func writeData<Data: DataProtocol>(_ data: Data) {
            createFileIfNeeded()

            if #available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
                try? outputStream.write(contentsOf: data)
            } else {
                try? outputStream.write(Foundation.Data(data))
            }
        }

        public func writeBytes<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
            createFileIfNeeded()

            if #available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
                try? outputStream.write(contentsOf: Data(bytes))
            } else {
                try? outputStream.write(Data(bytes))
            }
        }

        public func readData(_ length: Int) -> Data? {
            guard fileExists else {
                return nil
            }

            let data: Data?

            if #available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
                data = (try? inputStream.read(upToCount: length))
            } else {
                data = (try? inputStream.readData(ofLength: length))
            }

            return data
        }

        public func readBytes(_ length: Int) -> [UInt8]? {
            guard fileExists, let data = readData(length) else {
                return nil
            }

            let count = data.count / MemoryLayout<UInt8>.size
            var bytes = [UInt8](repeating: 0, count: count)
            data.copyBytes(to: &bytes, count: count)

            return bytes
        }

        func moveReaderIndex(to index: Int) throws {
            guard fileExists else {
                return
            }

            try inputStream.seek(toOffset: UInt64(index))
        }

        func moveWriterIndex(to index: Int) throws {
            guard fileExists else {
                return
            }

            try outputStream.seek(toOffset: UInt64(index))
        }

        deinit {
            do {
                try _inputStream?.close()
                try _outputStream?.close()
            } catch {
                Log.failure(error)
            }
        }
    }
}
