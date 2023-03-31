/*
 See LICENSE for this package's licensing information.
*/

import Foundation

public struct ByteBuffer: Sendable, Hashable {

    private var _bytes: Internals.ByteBuffer

    init(_ bytes: Internals.ByteBuffer) {
        _bytes = bytes
    }
}

extension ByteBuffer {

    public var writableBytes: Int {
        _bytes.writableBytes
    }

    public var readableBytes: Int {
        _bytes.readableBytes
    }

    public var capacity: Int {
        _bytes.capacity
    }

    public var storageCapacity: Int {
        _bytes.storageCapacity
    }

    public mutating func reserveCapacity(_ minimumCapacity: Int) {
        _bytes.reserveCapacity(minimumCapacity)
    }

    public mutating func reserveCapacity(minimumWritableBytes: Int) {
        _bytes.reserveCapacity(minimumWritableBytes: minimumWritableBytes)
    }

    public func getSlice(at index: Int, length: Int) -> ByteBuffer? {
        _bytes.getSlice(at: index, length: length).map(Self.init)
    }

    public mutating func discardReadBytes() -> Bool {
        _bytes.discardReadBytes()
    }

    public var readerIndex: Int {
        _bytes.readableBytes
    }

    public var writerIndex: Int {
        _bytes.writerIndex
    }

    public mutating func clear() {
        _bytes.clear()
    }

    public mutating func clear(minimumCapacity: Int) {
        _bytes.clear(minimumCapacity: minimumCapacity)
    }
}

extension ByteBuffer {

    public mutating func writeBytes<Bytes: Sequence>(
        _ bytes: Bytes
    ) -> Int where Bytes.Element == UInt8 {
        _bytes.writeBytes(bytes)
    }

    public mutating func writeData<Data: DataProtocol>(_ data: Data) -> Int {
        _bytes.writeData(data)
    }

    public mutating func readBytes(length: Int) -> [UInt8]? {
        _bytes.readBytes(length: length)
    }

    public mutating func readData(length: Int) -> Data? {
        _bytes.readData(length: length)
    }

    public mutating func moveReaderIndex(to offset: Int) {
        _bytes.moveReaderIndex(to: offset)
    }

    public mutating func moveWriterIndex(to offset: Int) {
        _bytes.moveWriterIndex(to: offset)
    }
}
