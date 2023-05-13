/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import NIOFoundationCompat

extension Internals {

    struct BodySequence: Sendable, Sequence {

        // MARK: - Internal properties

        let size: Int
        let fragmentSize: Int

        var isEmpty: Bool {
            buffers.isEmpty
        }

        // MARK: - Private properties

        private let buffers: [BufferProtocol]

        // MARK: - Inits

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

        // MARK: - Internal methods

        func makeIterator() -> Iterator {
            Iterator(
                buffers: buffers,
                size: size,
                fragment: fragmentSize
            )
        }
    }
}

extension Internals.BodySequence {

    struct Iterator: Sendable, IteratorProtocol {

        // MARK: - Internal properties

        let size: Int
        let fragment: Int
        private(set) var buffers: [BufferProtocol]

        // MARK: - Private properties

        private var bytes: NIOCore.ByteBuffer

        // MARK: - Inits

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

        // MARK: - Internal methods

        mutating func next() -> NIOCore.ByteBuffer? {
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
