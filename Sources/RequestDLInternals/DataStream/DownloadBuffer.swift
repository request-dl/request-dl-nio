/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

struct DownloadBuffer {

    private var buffer: DataBuffer?
    private let readingMode: Response.ReadingMode
    let stream: DataStream<DataBuffer>

    init(readingMode: Response.ReadingMode) {
        self.buffer = DataBuffer()
        self.readingMode = readingMode
        self.stream = .init()
    }

    mutating func append(_ byteBuffer: ByteBuffer) {
        guard var buffer = buffer else {
            return
        }

        defer { self.buffer = buffer }

        var byteBuffer = byteBuffer

        switch readingMode {
        case .length(let length):
            while byteBuffer.readableBytes > .zero {
                let receivedBytes = byteBuffer.readableBytes
                let currentBytes = buffer.readableBytes

                let availableBytes = length - currentBytes
                let readableBytes = receivedBytes > availableBytes ? availableBytes : receivedBytes

                if let data = byteBuffer.readData(length: readableBytes) {
                    buffer.writeData(data)
                }

                if buffer.readableBytes == length {
                    var dataBuffer = DataBuffer()
                    dataBuffer.writeBuffer(&buffer)

                    stream.append(.success(dataBuffer))

                    buffer.moveReaderIndex(to: .zero)
                    buffer.moveWriterIndex(to: .zero)
                }
            }
        case .separator(let separator):
            let length = separator.count

            while let bytes = byteBuffer.readBytes(length: length) {
                buffer.writeBytes(bytes)

                guard bytes == separator else {
                    let index = byteBuffer.readerIndex - (length - 1)
                    byteBuffer.moveReaderIndex(to: index)
                    continue
                }

                var dataBuffer = DataBuffer()
                dataBuffer.writeBuffer(&buffer)

                stream.append(.success(dataBuffer))

                buffer.moveReaderIndex(to: .zero)
                buffer.moveWriterIndex(to: .zero)
            }
        }
    }

    mutating func close() {
        guard var buffer = buffer else {
            return
        }

        if let data = buffer.readData(buffer.readableBytes) {
            stream.append(.success(.init(data)))
        }

        self.buffer = nil
        stream.close()
    }

    mutating func failed(_ error: Error) {
        buffer = nil
        stream.append(.failure(error))
    }
}

extension Response {

    public enum ReadingMode: Equatable {
        case length(Int)
        case separator([UInt8])
    }
}
