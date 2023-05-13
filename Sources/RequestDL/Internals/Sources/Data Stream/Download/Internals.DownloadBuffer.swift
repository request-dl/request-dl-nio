/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

extension Internals {

    struct DownloadBuffer {

        private var buffer: DataBuffer?
        private let readingMode: Internals.Response.ReadingMode
        let stream: DataStream<DataBuffer>

        init(readingMode: Internals.Response.ReadingMode) {
            self.buffer = DataBuffer()
            self.readingMode = readingMode
            self.stream = .init()
        }

        mutating func append(_ incomeBytes: BufferProtocol) {
            guard var buffer = buffer else {
                return
            }

            defer { self.buffer = buffer }

            var incomeBytes = incomeBytes

            switch readingMode {
            case .length(let length):
                while incomeBytes.readableBytes > .zero {
                    let receivedBytes = incomeBytes.readableBytes
                    let currentBytes = buffer.readableBytes

                    let availableBytes = length - currentBytes
                    let readableBytes = receivedBytes > availableBytes ? availableBytes : receivedBytes

                    if let data = incomeBytes.readData(readableBytes) {
                        buffer.writeData(data)
                    }

                    if buffer.readableBytes == length {
                        var dataBuffer = DataBuffer()
                        dataBuffer.writeBuffer(&buffer)

                        dispatch(.success(dataBuffer))

                        buffer.moveReaderIndex(to: .zero)
                        buffer.moveWriterIndex(to: .zero)
                    }
                }
            case .separator(let separator):
                let length = separator.count

                while let bytes = incomeBytes.readBytes(length) {
                    buffer.writeBytes(bytes)

                    guard bytes == separator else {
                        let index = incomeBytes.readerIndex - (length - 1)
                        incomeBytes.moveReaderIndex(to: index)
                        continue
                    }

                    var dataBuffer = DataBuffer()
                    dataBuffer.writeBuffer(&buffer)

                    dispatch(.success(dataBuffer))

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
                dispatch(.success(.init(data)))
            }

            self.buffer = nil
            stream.close()
        }

        mutating func failed(_ error: Error) {
            buffer = nil
            dispatch(.failure(error))
        }

        private mutating func dispatch(_ dataBuffer: Result<DataBuffer, Error>) {
            stream.append(dataBuffer)
        }
    }
}

extension Internals.Response {

    enum ReadingMode: Hashable {
        case length(Int)
        case separator([UInt8])
    }
}
