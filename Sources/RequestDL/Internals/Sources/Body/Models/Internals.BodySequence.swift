/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import NIOFoundationCompat

extension Internals {

    struct BodySequence: Sendable, Sequence {

        struct Iterator: Sendable, IteratorProtocol {

            // MARK: - Internal properties

            let chunkSize: Int
            let totalSize: Int
            private(set) var buffers: [Internals.AnyBuffer]

            // MARK: - Private properties

            private var bytes: NIOCore.ByteBuffer

            // MARK: - Inits

            init(
                chunkSize: Int,
                totalSize: Int,
                buffers: [Internals.AnyBuffer]
            ) {
                self.chunkSize = chunkSize
                self.totalSize = totalSize
                self.buffers = buffers
                self.bytes = .init(repeating: .zero, count: chunkSize)
                bytes.moveReaderIndex(to: .zero)
                bytes.moveWriterIndex(to: .zero)
            }

            // MARK: - Internal methods

            mutating func next() -> NIOCore.ByteBuffer? {
                guard chunkSize > .zero else {
                    return nil
                }

                if bytes.writerIndex == chunkSize {
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

                let availableBytes = chunkSize - bytes.writerIndex
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

        // MARK: - Internal properties

        let chunkSize: Int
        let totalSize: Int

        var isEmpty: Bool {
            buffers.isEmpty
        }

        // MARK: - Private properties

        private let buffers: [Internals.AnyBuffer]

        // MARK: - Inits

        init(
            chunkSize: Int?,
            buffers: [Internals.AnyBuffer]
        ) {
            let totalSize = buffers.lazy
                .map(\.estimatedBytes)
                .reduce(.zero, +)

            self.chunkSize = chunkSize ?? {
                if totalSize == .zero {
                    return .zero
                }

                let chunkSize = Int(floor(Double(totalSize) / 10_000))
                return chunkSize == .zero && totalSize > .zero ? 1 : chunkSize
            }()
            self.totalSize = totalSize
            self.buffers = buffers
        }

        // MARK: - Internal methods

        func makeIterator() -> Iterator {
            Iterator(
                chunkSize: chunkSize,
                totalSize: totalSize,
                buffers: buffers
            )
        }
    }
}
