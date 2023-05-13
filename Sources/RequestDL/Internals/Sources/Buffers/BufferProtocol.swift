/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol BufferProtocol: Sendable {

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

    func getData(at index: Int, length: Int) -> Data? {
        var mutableSelf = self

        guard index + length <= mutableSelf.writerIndex else {
            return nil
        }

        mutableSelf.moveReaderIndex(to: index)
        return mutableSelf.readData(length)
    }

    func getBytes(at index: Int, length: Int) -> [UInt8]? {
        var mutableSelf = self

        guard index + length <= mutableSelf.writerIndex else {
            return nil
        }

        mutableSelf.moveReaderIndex(to: index)
        return mutableSelf.readBytes(length)
    }
}

extension BufferProtocol {

    func setBytes<S: Sequence>(_ bytes: S) where S.Element == UInt8 {
        var mutableSelf = self
        mutableSelf.writeBytes(bytes)
    }

    func setData<Data: DataProtocol>(_ data: Data) {
        var mutableSelf = self
        mutableSelf.writeData(data)
    }

    func setBytes<S: Sequence>(_ bytes: S, at index: Int) where S.Element == UInt8 {
        var mutableSelf = self
        mutableSelf.moveWriterIndex(to: index)
        mutableSelf.writeBytes(bytes)
    }

    func setData<Data: DataProtocol>(_ data: Data, at index: Int) {
        var mutableSelf = self
        mutableSelf.moveWriterIndex(to: index)
        mutableSelf.writeData(data)
    }
}
