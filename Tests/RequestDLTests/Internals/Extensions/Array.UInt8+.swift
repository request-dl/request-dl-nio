//
// See LICENSE for this package's licensing information.
//

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
#endif

extension [UInt8] {

    func split(by size: Int) async -> [Data] {
        var buffer = await Internals.DataBuffer(self)
        var items = [Data]()
        var readBytes = 0

        func nextSize() -> Int {
            if buffer.readableBytes - size < .zero {
                return buffer.readableBytes
            } else {
                return size
            }
        }

        while let data = await buffer.readData(nextSize()) {
            readBytes += data.count
            items.append(data)
        }

        return items
    }

    func split(separator: [UInt8]) async -> [Data] {
        var buffer = await Internals.DataBuffer(self)
        var chunk = await Internals.DataBuffer()
        var items = [Data]()

        func nextSize() -> Int {
            if buffer.readableBytes - separator.count < .zero {
                return buffer.readableBytes
            } else {
                return separator.count
            }
        }

        while let bytes = await buffer.readBytes(nextSize()) {
            if bytes == separator {
                await chunk.writeBytes(bytes)
                if let data = await chunk.readData(chunk.readableBytes) {
                    items.append(data)
                    chunk.moveReaderIndex(to: .zero)
                    chunk.moveWriterIndex(to: .zero)
                } else {
                    break
                }
            } else {
                await chunk.writeBytes(Data(bytes)[0...0])
                if buffer.readableBytes != .zero {
                    buffer.moveReaderIndex(to: (buffer.readerIndex + 1) - separator.count)
                }
            }
        }

        if let data = await chunk.readData(chunk.readableBytes) {
            items.append(data)
        }

        return items
    }
}
