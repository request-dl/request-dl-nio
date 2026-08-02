//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
import struct Foundation.Data
import protocol Foundation.DataProtocol
#endif

protocol _BufferRepresentable<Stream>: Sendable {

    associatedtype Stream: StreamBuffer

    var readerIndex: Int { get }

    var readableBytes: Int { get }

    var writerIndex: Int { get }

    /// Bytes already in the store that sit past the writer index.
    ///
    /// Renamed from `writableBytes`, which read as remaining capacity. These buffers grow on
    /// demand, so there is no capacity to report, and the number actually says how much the
    /// next write would overwrite.
    var overwritableBytes: Int { get }

    var estimatedBytes: Int { get }

    init(_ url: URL)

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

    // The index-less `setData(_:)` and `setBytes(_:)` are gone. They wrote at the current
    // writer index without moving it, which put the bytes outside the readable range with no
    // way to reach them, and left the next write pointed at the same index to overwrite them.
    // There was no call that both compiled and did something useful.

    func setData<Data: DataProtocol>(_ data: Data, at index: Int)

    func setBytes<Bytes: Sequence>(_ bytes: Bytes, at index: Int) where Bytes.Element == UInt8

    /// Drops every byte and rewinds both cursors, letting the store shrink back.
    mutating func clear()

    /// Releases the open streams without discarding anything.
    func close()
}

extension Internals.Buffer: _BufferRepresentable {}
