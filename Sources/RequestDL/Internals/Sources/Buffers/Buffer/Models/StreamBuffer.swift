//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import protocol Foundation.DataProtocol
#endif

protocol StreamBuffer<URL>: Sendable {

    associatedtype URL: BufferURL

    init(readingFrom url: URL) throws

    init(writingTo url: URL) throws

    var offset: UInt64 { get }

    func seek(to offset: UInt64) throws

    func writeData<Data: DataProtocol>(_ data: Data) throws

    func readData(length: UInt64) throws -> Data?

    func close() throws
}
