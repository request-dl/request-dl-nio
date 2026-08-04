//
// See LICENSE for this package's licensing information.
//

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.URL
// import struct Foundation.Data
// import protocol Foundation.DataProtocol
#endif

/// The shape of ``Internals/Buffer``, so callers can hold one without naming its stream type.
///
/// ## Concurrency
///
/// Every mutating requirement is `async`, which means exclusive access to `self` held across a
/// suspension. That is legal for a local `var` and rejected for a stored property of a class or
/// an actor. Anything keeping a buffer as a property has to move it into a local, operate, and
/// write it back, or wrap it in a type that owns the serialization.
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
    var overwritableBytes: Int { get async }

    /// Bytes in the shared store, regardless of where this cursor sits.
    var estimatedBytes: Int { get async }

    init(_ url: URL) async

    init(_ url: Internals.ByteURL) async

    init<Bytes: DataProtocol & Sendable>(_ data: Bytes) async

    init<Bytes: Sequence & Sendable>(_ bytes: Bytes) async where Bytes.Element == UInt8

    init(_ string: String) async

    init(_ staticString: StaticString) async

    init() async

    init<OtherStream: StreamBuffer>(_ buffer: Internals.Buffer<OtherStream>) async

    mutating func moveReaderIndex(to index: Int)

    /// Reads forward from the reader index and advances it by however much arrived.
    mutating func readData(_ length: Int) async -> Data?

    /// - Note: Same semantics as ``readData(_:)``.
    mutating func readBytes(_ length: Int) async -> [UInt8]?

    /// Reads the whole readable range without moving the cursor.
    func getData() async -> Data?

    /// Reads the whole readable range without moving the cursor.
    func getBytes() async -> [UInt8]?

    /// Reads an absolute range without moving the cursor. Out of range answers `nil`.
    func getData(at index: Int, length: Int) async -> Data?

    /// Reads an absolute range without moving the cursor. Out of range answers `nil`.
    func getBytes(at index: Int, length: Int) async -> [UInt8]?

    mutating func moveWriterIndex(to index: Int)

    /// Writes at the writer index and advances it. Failure is silent.
    mutating func writeData<Bytes: DataProtocol & Sendable>(_ data: Bytes) async

    /// - Note: Same semantics as ``writeData(_:)``.
    mutating func writeBytes<Bytes: Sequence & Sendable>(_ bytes: Bytes) async where Bytes.Element == UInt8

    /// Drains `buffer` into this one.
    mutating func writeBuffer<OtherStream: StreamBuffer>(_ buffer: inout Internals.Buffer<OtherStream>) async

    // The index-less `setData(_:)` and `setBytes(_:)` are gone. They wrote at the current
    // writer index without moving it, which put the bytes outside the readable range with no
    // way to reach them, and left the next write pointed at the same index to overwrite them.
    // There was no call that both compiled and did something useful.

    /// Overwrites bytes already in the store, leaving the cursor where it was.
    func setData<Bytes: DataProtocol & Sendable>(_ data: Bytes, at index: Int) async throws

    /// Overwrites bytes already in the store, leaving the cursor where it was.
    func setBytes<Bytes: Sequence & Sendable>(_ bytes: Bytes, at index: Int) async where Bytes.Element == UInt8

    /// Drops every byte and rewinds both cursors, letting the store shrink back.
    mutating func clear() async

    /// Releases the open streams without discarding anything.
    func close() async throws
}

extension Internals.Buffer: _BufferRepresentable {}
