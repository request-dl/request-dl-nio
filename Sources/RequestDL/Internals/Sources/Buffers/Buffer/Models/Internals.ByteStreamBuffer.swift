//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import protocol Foundation.DataProtocol
#endif

extension Internals {

    /// A stream over an in memory store.
    ///
    /// Everything here is synchronous underneath. The `async` is protocol conformance, not
    /// suspension, and no operation ever waits.
    final class ByteStreamBuffer: StreamBuffer {

        typealias URL = Internals.ByteBufferURL

        // MARK: - Internal properties

        var offset: UInt64 {
            get async throws {
                try byteHandle.offset()
            }
        }

        // MARK: - Private properties

        private let byteHandle: Internals.ByteHandle

        // MARK: - Inits

        init(readingFrom url: URL) async throws {
            byteHandle = .init(forReadingFrom: url.absoluteURL())
        }

        init(writingTo url: URL) async throws {
            byteHandle = .init(forWritingTo: url.absoluteURL())
        }

        // MARK: - Internal methods

        func seek(to offset: UInt64) async throws {
            try byteHandle.seek(toOffset: offset)
        }

        func writeData<Bytes: DataProtocol & Sendable>(_ data: Bytes) async throws {
            try byteHandle.write(contentsOf: data)
        }

        func readData(length: UInt64) async throws -> Data? {
            try byteHandle.read(upToCount: Int(length))
        }

        func close() async throws {
            try byteHandle.close()
        }
    }
}
