/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import NIOFoundationCompat

public struct AsyncBytes: AsyncSequence {
    public typealias Element = UInt8

    public typealias AsyncStream = AsyncThrowingStream<Element, Error>

    fileprivate let asyncStream: AsyncThrowingStream<ByteBuffer, Error>

    init(_ dataStream: DataStream<ByteBuffer>) {
        self.asyncStream = dataStream.asyncStream()
    }

    public func makeAsyncIterator() -> Iterator {
        Iterator(asyncStream.makeAsyncIterator())
    }
}

extension AsyncBytes {

    public struct Iterator: AsyncIteratorProtocol {

        public typealias Element = UInt8

        var referenceIterator: AsyncThrowingStream<ByteBuffer, Error>.AsyncIterator
        private var index: Int = .zero
        private var buffer: Array<UInt8>.SubSequence = .init()

        init(_ referenceIterator: AsyncThrowingStream<ByteBuffer, Error>.AsyncIterator) {
            self.referenceIterator = referenceIterator
        }

        public mutating func next() async throws -> UInt8? {
            if let byte = buffer.first {
                buffer.removeFirst()
                return byte
            }

            guard var byteBuffer = try await referenceIterator.next() else {
                return nil
            }

            byteBuffer.moveReaderIndex(to: index)
            let bytes = byteBuffer.readBytes(length: byteBuffer.readableBytes) ?? []
            index = byteBuffer.readerIndex

            return bytes.first.map {
                buffer = bytes.dropFirst()
                return $0
            }
        }
    }
}

extension AsyncBytes {

    fileprivate func data() async throws -> Data {
        var lastByteBuffer: ByteBuffer?

        for try await byteBuffer in asyncStream {
            lastByteBuffer = byteBuffer
        }

        if let lastByteBuffer {
            return Data(buffer: lastByteBuffer)
        } else {
            return Data()
        }
    }
}

extension Data {

    public init(_ asyncBytes: AsyncBytes) async throws {
        self = try await asyncBytes.data()
    }
}
