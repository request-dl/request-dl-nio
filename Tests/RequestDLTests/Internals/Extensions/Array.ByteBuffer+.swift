/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
@testable import RequestDL

extension Array<ByteBuffer> {

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
