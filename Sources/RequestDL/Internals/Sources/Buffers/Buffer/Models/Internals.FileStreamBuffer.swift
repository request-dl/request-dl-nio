//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import class Foundation.FileHandle
import protocol Foundation.DataProtocol
import struct Foundation.Data
#endif

extension Internals {

    final class FileStreamBuffer: StreamBuffer {

        typealias URL = Internals.FileBufferURL

        // MARK: - Internal properties

        var offset: UInt64 {
            (try? fileHandle.offset()) ?? .zero
        }

        // MARK: - Private properties

        #if canImport(FoundationEssentials)
        private let fileHandle: FoundationEssentials.FileHandle
        #else
        private let fileHandle: Foundation.FileHandle
        #endif

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
