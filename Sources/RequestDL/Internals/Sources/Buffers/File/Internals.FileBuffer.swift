/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    // TODO: - Refactor

    struct FileBuffer: BufferProtocol {

        private final class Storage: @unchecked Sendable {

            // MARK: - Internals properties

            var writerIndex: Int {
                lock.withLock {
                    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
                        return (try? _storedOutputStream?.offset()).map(Int.init) ?? .zero
                    } else {
                        return (_storedOutputStream?.offsetInFile).map(Int.init) ?? .zero
                    }
                }
            }

            var readerIndex: Int {
                lock.withLock {
                    if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
                        return (try? _storedInputStream?.offset()).map(Int.init) ?? .zero
                    } else {
                        return (_storedInputStream?.offsetInFile).map(Int.init) ?? .zero
                    }
                }
            }

            var writtenBytes: Int {
                lock.withLock {
                    (try? FileManager.default.attributesOfItem(atPath: path)[.size]) as? Int ?? .zero
                }
            }

            // MARK: - Private properties

            private let lock = Lock()
            private let url: URL

            private var path: String {
                url.absolutePath(percentEncoded: false)
            }

            // MARK: - Unsafe properties

            private lazy var _fileExists: Bool = {
                FileManager.default.fileExists(atPath: path)
            }()

            private var _storedInputStream: FileHandle?
            private var _storedOutputStream: FileHandle?

            private var _inputStream: FileHandle {
                get throws {
                    if let stream = _storedInputStream {
                        return stream
                    }

                    let stream = try FileHandle(forReadingFrom: url)
                    _storedInputStream = stream
                    return stream
                }
            }

            private var _outputStream: FileHandle {
                get throws {
                    if let stream = _storedOutputStream {
                        return stream
                    }

                    let stream = try FileHandle(forWritingTo: url)
                    _storedOutputStream = stream
                    return stream
                }
            }

            // MARK: - Inits

            init(_ url: URL) {
                self.url = url
            }

            // MARK: - Internal methods

            func writeData<Data: DataProtocol>(_ data: Data) {
                lock.withLock {
                    _createFileIfNeeded()

                    if #available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
                        try? _outputStream.write(contentsOf: data)
                    } else {
                        try? _outputStream.write(Foundation.Data(data))
                    }
                }
            }

            func writeBytes<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
                lock.withLock {
                    _createFileIfNeeded()

                    if #available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
                        try? _outputStream.write(contentsOf: Data(bytes))
                    } else {
                        try? _outputStream.write(Data(bytes))
                    }
                }
            }

            func readData(_ length: Int) -> Data? {
                lock.withLock {
                    _readData(length)
                }
            }

            func readBytes(_ length: Int) -> [UInt8]? {
                lock.withLock {
                    guard _fileExists, let data = _readData(length) else {
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
                    guard _fileExists else {
                        return
                    }

                    try _inputStream.seek(toOffset: UInt64(index))
                }
            }

            func moveWriterIndex(to index: Int) throws {
                try lock.withLockVoid {
                    guard _fileExists else {
                        return
                    }

                    try _outputStream.seek(toOffset: UInt64(index))
                }
            }

            // MARK: - Unsafe methods

            private func _createFileIfNeeded() {
                guard !_fileExists else {
                    return
                }

                _fileExists = FileManager.default.createFile(atPath: path, contents: nil)
            }

            private func _readData(_ length: Int) -> Data? {
                guard _fileExists else {
                    return nil
                }

                let data: Data?

                if #available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
                    data = (try? _inputStream.read(upToCount: length))
                } else {
                    data = (try? _inputStream.readData(ofLength: length))
                }

                return data
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

        var readableBytes: Int {
            writerIndex - readerIndex
        }

        var writableBytes: Int {
            storage.writtenBytes - writerIndex
        }

        var estimatedBytes: Int {
            storage.writtenBytes
        }

        private(set) var readerIndex: Int = .zero

        private(set) var writerIndex: Int

        // MARK: - Private properties

        private let storage: Storage

        // MARK: - Inits

        init(_ url: URL) {
            self.init(storage: .init(url))
        }

        init(_ url: Internals.ByteURL) {
            self.init(Internals.DataBuffer(url))
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
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("RequestDL.FileBuffer.\(UUID()).temp")
            self.init(url)
        }

        init<Buffer: BufferProtocol>(_ buffer: Buffer) {
            if let fileBuffer = buffer as? Internals.FileBuffer {
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

        private init(storage: Storage) {
            self.storage = storage
            self.writerIndex = storage.writtenBytes
        }

        // MARK: - Internal methods

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
}
