//
// See LICENSE for this package's licensing information.
//

import NIOCore

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
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

    func resolveData() -> [Data] {
        compactMap {
            var mutableBuffer = $0
            return mutableBuffer.readData($0.writerIndex)
        }
    }
}
