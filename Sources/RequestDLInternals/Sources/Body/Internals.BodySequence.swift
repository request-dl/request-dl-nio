//
// See LICENSE for this package's licensing information.
//

import NIOCore

extension Internals {

    /// Cuts a list of buffers into fixed size chunks for the request body writer.
    package struct BodySequence: Sendable, AsyncSequence {

        package struct AsyncIterator: Sendable, AsyncIteratorProtocol {

            // MARK: - Internal properties

            package let chunkSize: Int
            package let totalSize: Int
            private(set) var buffers: [Internals.AnyBuffer]

            // MARK: - Private properties

            private var bytes: NIOCore.ByteBuffer

            // MARK: - Inits

            package init(
                chunkSize: Int,
                totalSize: Int,
                buffers: [Internals.AnyBuffer]
            ) {
                self.chunkSize = chunkSize
                self.totalSize = totalSize
                self.buffers = buffers
                // Allocated once at full size and then rewound, so the capacity is reused for
                // every chunk instead of growing again per iteration.
                self.bytes = .init(repeating: .zero, count: chunkSize)
                bytes.moveReaderIndex(to: .zero)
                bytes.moveWriterIndex(to: .zero)
            }

            // MARK: - Internal methods

            /// Fills one chunk from the head of `buffers`.
            ///
            /// Iterative on purpose. Recursing once per source buffer meant the stack depth
            /// tracked the number of buffers feeding a single chunk, which a body assembled
            /// from many small parts turns into an overflow.
            package mutating func next() async -> NIOCore.ByteBuffer? {
                guard chunkSize > .zero else {
                    return nil
                }

                while bytes.writerIndex < chunkSize {
                    guard var buffer = buffers.first else {
                        break
                    }

                    let availableBytes = chunkSize - bytes.writerIndex
                    let length = Swift.min(buffer.readableBytes, availableBytes)

                    guard length > .zero else {
                        buffers.removeFirst()
                        continue
                    }

                    guard let data = await buffer.readData(length) else {
                        // The buffer advertised readable bytes and then failed to produce
                        // them. Dropping it sends a body shorter than the declared length and
                        // leaves the peer waiting for the rest, so at least say so in debug
                        // rather than letting it pass unnoticed.
                        //
                        // Through `Internals`, not `Swift`. The package has an override for
                        // this precisely so a test can intercept it, and calling the standard
                        // library directly walks straight past it.
                        Internals.assertionFailure(
                            "Buffer reported \(buffer.readableBytes) readable bytes but returned none"
                        )

                        buffers.removeFirst()
                        continue
                    }

                    bytes.writeBytes(data)

                    // The cursor advanced on the local copy, so it has to be written back.
                    // This is the one place the value semantics of `Internals.Buffer` are load
                    // bearing in this file: the array element is a distinct copy until it is
                    // reassigned.
                    if buffer.readableBytes == .zero {
                        buffers.removeFirst()
                    } else {
                        buffers[.zero] = buffer
                    }
                }

                guard bytes.readableBytes > .zero else {
                    return nil
                }

                let chunk = ByteBuffer(buffer: bytes)

                bytes.moveReaderIndex(to: .zero)
                bytes.moveWriterIndex(to: .zero)

                return chunk
            }
        }

        // MARK: - Private static properties

        /// How many chunks a body is aimed at, before the bounds below have their say.
        private static let targetChunkCount = 10_000

        private static let minimumChunkSize = 16 * 1_024

        private static let maximumChunkSize = 1_024 * 1_024

        // MARK: - Internal properties

        package let chunkSize: Int
        package let totalSize: Int

        package var isEmpty: Bool {
            buffers.isEmpty
        }

        // MARK: - Private properties

        private let buffers: [Internals.AnyBuffer]

        // MARK: - Inits

        package init(
            chunkSize: Int?,
            buffers: [Internals.AnyBuffer]
        ) {
            // `readableBytes`, not `estimatedBytes`. The iterator emits exactly what the
            // cursors can still read, while the estimate is the size of the whole store, so a
            // partially read buffer made this overstate the body and left the declared length
            // larger than what actually goes out. It also drops a stat call per file backed
            // buffer.
            let totalSize = buffers.lazy
                .map(\.readableBytes)
                .reduce(.zero, +)

            self.chunkSize = chunkSize ?? Self.defaultChunkSize(totalSize: totalSize)
            self.totalSize = totalSize
            self.buffers = buffers
        }

        // MARK: - Private static methods

        private static func defaultChunkSize(totalSize: Int) -> Int {
            guard totalSize > .zero else {
                return .zero
            }

            // Unclamped, `totalSize / 10_000` produced one byte chunks for anything under
            // 10 kB: a hundred byte request body became a hundred writes, each with its own
            // future and its own progress event.
            let target = Swift.max(totalSize / targetChunkCount, minimumChunkSize)
            return Swift.min(target, maximumChunkSize, totalSize)
        }

        // MARK: - Internal methods

        package func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(
                chunkSize: chunkSize,
                totalSize: totalSize,
                buffers: buffers
            )
        }
    }
}
