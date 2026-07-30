/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

extension Internals {

    final class FileStreamBuffer: StreamBuffer {

        typealias URL = Internals.FileBufferURL

        // MARK: - Internal properties

        var offset: UInt64 {
            (try? fileHandle.offset()) ?? .zero
        }

        // MARK: - Private properties

        private let fileHandle: Foundation.FileHandle

        // MARK: - Inits

        init(readingFrom url: URL) throws {
            fileHandle = try .init(forReadingFrom: url.absoluteURL())
        }

        init(writingTo url: URL) throws {
            fileHandle = try .init(forWritingTo: url.absoluteURL())
        }

        // MARK: - Internal methods

        func seek(to offset: UInt64) throws {
            try fileHandle.seek(toOffset: offset)
        }

        func writeData<Data: DataProtocol>(_ data: Data) throws {
            try fileHandle.write(contentsOf: data)
        }

        func readData(length: UInt64) throws -> Data? {
            try fileHandle.read(upToCount: Int(length))
        }

        func close() throws {
            try fileHandle.close()
        }
    }
}
