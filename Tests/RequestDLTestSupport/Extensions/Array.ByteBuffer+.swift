//
// See LICENSE for this package's licensing information.
//

import NIOCore

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
import NIOFoundationEssentialsCompat
#else
import struct Foundation.Data
#endif

extension [ByteBuffer] {

    func resolveData() -> [Data] {
        compactMap {
            var mutableBuffer = $0
            return mutableBuffer.readData(length: $0.writerIndex)
        }
    }
}

extension Array where Element: _BufferRepresentable {

    func resolveData() async -> [Data] {
        var items = [Data]()
        items.reserveCapacity(count)

        for buffer in self {
            var buffer = buffer

            guard let data = await buffer.readData(buffer.writerIndex) else {
                continue
            }

            items.append(data)
        }

        return items
    }
}
