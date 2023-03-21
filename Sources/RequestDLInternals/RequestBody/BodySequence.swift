/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore

struct BodySequence: Sequence {

    private let size: Int
    private let buffers: [BufferProtocol]

    init(
        buffers: [BufferProtocol],
        size: Int?
    ) {
        self.buffers = buffers
        self.size = size ?? {
            let totalBytes = buffers.lazy
                .map(\.estimatedBytes)
                .reduce(.zero, +)

            if totalBytes == .zero {
                return .zero
            }

            let fragments = Int(floor(Double(totalBytes) / 10_000))
            return fragments == .zero && totalBytes > .zero ? 1 : fragments
        }()
    }

    func makeIterator() -> Iterator {
        Iterator(
            buffers: buffers,
            size: size
        )
    }
}

extension BodySequence {

    class Iterator: IteratorProtocol {

        private var bytes: ByteBuffer?
        private(set) var buffers: [BufferProtocol]
        let size: Int

        init(
            buffers: [BufferProtocol],
            size: Int
        ) {
            self.buffers = buffers
            self.size = size
            self.bytes = .init(repeating: .zero, count: size)
            bytes?.moveReaderIndex(to: .zero)
            bytes?.moveWriterIndex(to: .zero)
        }

        func next() -> ByteBuffer? {
            guard size > .zero, var bytes = bytes else {
                return nil
            }

            if bytes.writerIndex == size {
                bytes.moveReaderIndex(to: .zero)
                self.bytes = .init(repeating: .zero, count: size)
                self.bytes?.moveReaderIndex(to: .zero)
                self.bytes?.moveWriterIndex(to: .zero)
                return bytes
            }

            guard var buffer = buffers.first else {
                self.bytes = nil
                bytes.moveReaderIndex(to: .zero)
                return bytes.readableBytes > .zero ? bytes : nil
            }

            let availableBytes = size - bytes.writerIndex
            let length = buffer.readableBytes > availableBytes ? availableBytes : buffer.readableBytes

            if let data = buffer.readData(length) {
                bytes.writeData(data)
                self.bytes = bytes

                if buffer.readableBytes == .zero {
                    buffers.removeFirst()
                } else {
                    buffers[.zero] = buffer
                }
            } else {
                buffers.removeFirst()
            }

            return next()
        }
    }
}
