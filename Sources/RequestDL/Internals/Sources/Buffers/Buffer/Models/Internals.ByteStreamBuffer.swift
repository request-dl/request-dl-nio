/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    final class ByteStreamBuffer: StreamBuffer {

        typealias URL = Internals.ByteBufferURL

        private let byteHandle: Internals.ByteHandle

        init(readingFrom url: URL) throws {
            byteHandle = .init(forReadingFrom: url.absoluteURL())
        }

        init(writingTo url: URL) throws {
            byteHandle = .init(forWritingTo: url.absoluteURL())
        }

        var offset: UInt64 {
            (try? byteHandle.offset()) ?? .zero
        }

        func seek(to offset: UInt64) throws {
            try byteHandle.seek(toOffset: offset)
        }

        func writeData<Data: DataProtocol>(_ data: Data) throws {
            try byteHandle.write(contentsOf: data)
        }

        func readData(length: UInt64) throws -> Data? {
            try byteHandle.read(upToCount: Int(length))
        }

        func close() throws {
            try byteHandle.close()
        }
    }
}
