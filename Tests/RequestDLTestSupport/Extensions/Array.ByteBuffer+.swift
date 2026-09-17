//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(NIOCore)
import NIOCore
#endif

#if canImport(FoundationEssentials)
import FoundationEssentials
#if canImport(NIOCore)
import NIOFoundationEssentialsCompat
#endif
#else
import struct Foundation.Data
#endif

#if canImport(NIOCore)
extension [ByteBuffer] {

    func resolveData() -> [Data] {
        compactMap {
            var mutableBuffer = $0
            return mutableBuffer.readData(length: $0.writerIndex)
        }
    }
}
#endif

extension [Internals.Bytes] {

    func resolveData() -> [Data] {
        map {
            var mutableBytes = $0
            return mutableBytes.asData()
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
