/*
 See LICENSE for this package's licensing information.
*/

import Foundation

protocol _BufferRepresentable<Stream>: Sendable {

    associatedtype Stream: StreamBuffer

    var readerIndex: Int { get }

    var readableBytes: Int { get }

    var writerIndex: Int { get }

    var writableBytes: Int { get }

    var estimatedBytes: Int { get }

    init(_ url: Foundation.URL)

    init(_ url: Internals.ByteURL)

    init<Data: DataProtocol>(_ data: Data)

    init<Bytes: Sequence>(_ bytes: Bytes) where Bytes.Element == UInt8

    init(_ string: String)

    init(_ staticString: StaticString)

    init()

    init<OtherStream: StreamBuffer>(_ buffer: Internals.Buffer<OtherStream>)

    mutating func moveReaderIndex(to index: Int)

    mutating func readData(_ length: Int) -> Data?

    mutating func readBytes(_ length: Int) -> [UInt8]?

    func getData() -> Data?

    func getBytes() -> [UInt8]?

    func getData(at index: Int, length: Int) -> Data?

    func getBytes(at index: Int, length: Int) -> [UInt8]?

    mutating func moveWriterIndex(to index: Int)

    mutating func writeData<Data: DataProtocol>(_ data: Data)

    mutating func writeBytes<Bytes: Sequence>(_ bytes: Bytes) where Bytes.Element == UInt8

    mutating func writeBuffer<OtherStream: StreamBuffer>(_ buffer: inout Internals.Buffer<OtherStream>)

    func setData<Data: DataProtocol>(_ data: Data)

    func setBytes<Bytes: Sequence>(_ bytes: Bytes) where Bytes.Element == UInt8

    func setData<Data: DataProtocol>(_ data: Data, at index: Int)

    func setBytes<Bytes: Sequence>(_ bytes: Bytes, at index: Int) where Bytes.Element == UInt8
}

extension Internals.Buffer: _BufferRepresentable {}
