/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol BufferProtocol {

    var readerIndex: Int { get }
    var writerIndex: Int { get }

    var readableBytes: Int { get }
    var writableBytes: Int { get }

    var estimatedBytes: Int { get }

    init<Data: DataProtocol>(_ data: Data)

    init<S: Sequence>(_ bytes: S) where S.Element == UInt8

    init(_ url: URL)

    init(_ url: Internals.ByteURL)

    init(_ string: String)

    init(_ staticString: StaticString)

    init<Buffer: BufferProtocol>(_ buffer: Buffer)

    init()

    mutating func writeData<Data: DataProtocol>(_ data: Data)

    mutating func writeBytes<S: Sequence>(_ bytes: S) where S.Element == UInt8

    mutating func writeBuffer<Buffer: BufferProtocol>(_ buffer: inout Buffer)

    mutating func readData(_ length: Int) -> Data?

    mutating func readBytes(_ length: Int) -> [UInt8]?

    mutating func moveReaderIndex(to index: Int)

    mutating func moveWriterIndex(to index: Int)
}

extension BufferProtocol {

    func getData() -> Data? {
        var mutableSelf = self
        return mutableSelf.readData(mutableSelf.readableBytes)
    }

    func getBytes() -> [UInt8]? {
        var mutableSelf = self
        return mutableSelf.readBytes(mutableSelf.readableBytes)
    }
}
