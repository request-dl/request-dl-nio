/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Internals {

    final class FileStreamBuffer: StreamBuffer {

        typealias URL = Internals.FileBufferURL

        var offset: UInt64 {
            if #available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
                return (try? fileHandle.offset()) ?? .zero
            } else {
                return fileHandle.offsetInFile
            }
        }

        private let fileHandle: Foundation.FileHandle

        init(readingFrom url: URL) throws {
            fileHandle = try .init(forReadingFrom: url.absoluteURL())
        }

        init(writingTo url: URL) throws {
            fileHandle = try .init(forWritingTo: url.absoluteURL())
        }

        func seek(to offset: UInt64) throws {
            try fileHandle.seek(toOffset: offset)
        }

        func writeData<Data: DataProtocol>(_ data: Data) throws {
            if #available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
                try fileHandle.write(contentsOf: data)
            } else {
                fileHandle.write(Foundation.Data(data))
            }
        }

        func readData(length: UInt64) throws -> Data? {
            if #available(macOS 10.15.4, iOS 13.4, watchOS 6.2, tvOS 13.4, *) {
                return try fileHandle.read(upToCount: Int(length))
            } else {
                return fileHandle.readData(ofLength: Int(length))
            }
        }

        func close() throws {
            if #available(macOS 10.15, iOS 13, watchOS 6.0, tvOS 13, *) {
                try fileHandle.close()
            } else {
                fileHandle.closeFile()
            }
        }
    }
}
