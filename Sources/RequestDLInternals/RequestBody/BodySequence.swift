/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

struct BodySequence: Sequence {

    let size: Int
    let fragmentSize: Int
    private let buffers: [BufferProtocol]

    init(
        buffers: [BufferProtocol],
        size fragment: Int?
    ) {
        let size = buffers.lazy
            .map(\.estimatedBytes)
            .reduce(.zero, +)

        self.buffers = buffers
        self.size = size
        self.fragmentSize = fragment ?? {
            if size == .zero {
                return .zero
            }

            let fragments = Int(floor(Double(size) / 10_000))
            return fragments == .zero && size > .zero ? 1 : fragments
        }()
    }

    func makeIterator() -> Iterator {
        Iterator(
            buffers: buffers,
            size: size,
            fragment: fragmentSize
        )
    }
}

extension BodySequence {

    struct Iterator: IteratorProtocol {

        private var bytes: ByteBuffer
        private(set) var buffers: [BufferProtocol]
        let size: Int
        let fragment: Int

        init(
            buffers: [BufferProtocol],
            size: Int,
            fragment: Int
        ) {
            self.buffers = buffers
            self.size = size
            self.fragment = fragment
            self.bytes = .init(repeating: .zero, count: fragment)
            bytes.moveReaderIndex(to: .zero)
            bytes.moveWriterIndex(to: .zero)
        }

        mutating func next() -> ByteBuffer? {
            guard fragment > .zero else {
                return nil
            }

            if bytes.writerIndex == fragment {
                let chunk = ByteBuffer(buffer: bytes)
                bytes.moveReaderIndex(to: .zero)
                bytes.moveWriterIndex(to: .zero)
                return chunk
            }

            guard var buffer = buffers.first else {
                let chunk = ByteBuffer(buffer: bytes)
                bytes.moveReaderIndex(to: .zero)
                bytes.moveWriterIndex(to: .zero)
                return chunk.readableBytes > .zero ? chunk : nil
            }

            let availableBytes = fragment - bytes.writerIndex
            let length = buffer.readableBytes > availableBytes ? availableBytes : buffer.readableBytes

            guard let data = buffer.readData(length) else {
                buffers.removeFirst()
                return next()
            }

            bytes.writeData(data)

            if buffer.readableBytes == .zero {
                buffers.removeFirst()
            } else {
                buffers[.zero] = buffer
            }

            return next()
        }
    }
}
