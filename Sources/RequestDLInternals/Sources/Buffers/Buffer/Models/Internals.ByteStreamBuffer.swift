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
    package final class ByteStreamBuffer: StreamBuffer {

        package typealias URL = Internals.ByteBufferURL

        // MARK: - Internal properties

        package var offset: UInt64 {
            get async throws {
                try byteHandle.offset()
            }
        }

        // MARK: - Private properties

        private let byteHandle: Internals.ByteHandle

        // MARK: - Inits

        package init(readingFrom url: URL) async throws {
            byteHandle = .init(forReadingFrom: url.absoluteURL())
        }

        package init(writingTo url: URL) async throws {
            byteHandle = .init(forWritingTo: url.absoluteURL())
        }

        // MARK: - Internal methods

        package func seek(to offset: UInt64) async throws {
            try byteHandle.seek(toOffset: offset)
        }

        package func writeData<Bytes: DataProtocol & Sendable>(_ data: Bytes) async throws {
            try byteHandle.write(contentsOf: data)
        }

        package func readData(length: UInt64) async throws -> Data? {
            // Clamped: this is "up to", and the store hands back what is there. `Int` is 32 bits on
            // watchOS arm64_32, where a `UInt64` past 2 GiB would trap.
            try byteHandle.read(upToCount: Int(clamping: length))
        }

        package func close() async throws {
            try byteHandle.close()
        }
    }
}
