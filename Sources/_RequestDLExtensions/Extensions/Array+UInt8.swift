/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import RequestDLInternals

extension Array<UInt8> {

    public func split(by size: Int) -> [Data] {
        var buffer = DataBuffer(self)
        var items = [Data]()
        var readedBytes = 0

        func nextSize() -> Int {
            if buffer.readableBytes - size < .zero {
                return buffer.readableBytes
            } else {
                return size
            }
        }

        while let data = buffer.readData(nextSize()) {
            readedBytes += data.count
            items.append(data)
        }

        return items
    }

    public func split(separator: [UInt8]) -> [Data] {
        var buffer = DataBuffer(self)
        var chunk = DataBuffer()
        var items = [Data]()

        func nextSize() -> Int {
            if buffer.readableBytes - separator.count < .zero {
                return buffer.readableBytes
            } else {
                return separator.count
            }
        }

        while let bytes = buffer.readBytes(nextSize()) {
            if bytes == separator {
                chunk.writeBytes(bytes)
                if let data = chunk.readData(chunk.readableBytes) {
                    items.append(data)
                    chunk.moveReaderIndex(to: .zero)
                    chunk.moveWriterIndex(to: .zero)
                } else {
                    break
                }
            } else {
                chunk.writeBytes(Data(bytes)[0...0])
                if buffer.readableBytes != .zero {
                    buffer.moveReaderIndex(to: (buffer.readerIndex + 1) - separator.count)
                }
            }
        }

        if let data = chunk.readData(chunk.readableBytes) {
            items.append(data)
        }

        return items
    }
}