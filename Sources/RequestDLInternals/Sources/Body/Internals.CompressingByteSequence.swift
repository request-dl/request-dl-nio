//
// See LICENSE for this package's licensing information.
//

import NIOCore

extension Internals {

    /// Wraps `source` so each chunk is compressed as it's pulled, instead of draining the whole
    /// source into memory before compression starts: the actual upload begins as soon as the
    /// first compressed bytes exist, and only ever holds one chunk's worth of the original body
    /// in memory at a time.
    ///
    /// Generic over its source (rather than hardwired to `Internals.BodySequence`) because
    /// `RequestDLInternals` cannot depend back on `RequestDL`, where `RequestBody`, the actual
    /// source this wraps in practice, is defined.
    package struct CompressingByteSequence<Source: AsyncSequence & Sendable>: Sendable, AsyncSequence
    where Source.Element == ByteBuffer {

        package struct AsyncIterator: AsyncIteratorProtocol {

            // MARK: - Private properties

            private var sourceIterator: Source.AsyncIterator
            private let algorithm: any Internals.CompressionAlgorithm
            private var stream: (any Internals.CompressorStream)?
            private var isFinished = false

            // MARK: - Inits

            fileprivate init(sourceIterator: Source.AsyncIterator, algorithm: any Internals.CompressionAlgorithm) {
                self.sourceIterator = sourceIterator
                self.algorithm = algorithm
            }

            // MARK: - Internal methods

            /// Created lazily here, on the first call, rather than in `makeAsyncIterator()`:
            /// `AsyncIteratorProtocol.makeAsyncIterator()` isn't `throws`, and creating a
            /// `Compressor`'s stream (`Decompressor`'s own `callAsFunction()` counterpart) is
            /// allowed to fail.
            package mutating func next() async throws -> ByteBuffer? {
                guard !isFinished else {
                    return nil
                }

                // Pulled into a local, non-`Optional` binding for the rest of this call, and
                // written back below, since `CompressorStream`'s `callAsFunction`/`finish` are
                // `mutating`, so calling them through `self.stream` directly would need force
                // unwrapping it on every use instead of just once, here, right after creating it.
                var stream = try self.stream ?? algorithm()
                defer { self.stream = stream }

                while let chunk = try await sourceIterator.next() {
                    let compressed = try stream(compressing: chunk)

                    if compressed.readableBytes > .zero {
                        return compressed
                    }
                }

                isFinished = true
                let tail = try stream.finish()
                return tail.readableBytes > .zero ? tail : nil
            }
        }

        package typealias Element = ByteBuffer

        // MARK: - Internal properties

        /// Exposed so `RequestBody.totalSize`/`.chunkSize` can report the *original*,
        /// pre-compression body's own values as best-effort estimates. See that type's own
        /// doc comments for why those, not the (not-yet-known) compressed size, are what a
        /// compressing body reports there.
        package let source: Source

        // MARK: - Private properties

        private let algorithm: any Internals.CompressionAlgorithm

        // MARK: - Inits

        package init(source: Source, algorithm: any Internals.CompressionAlgorithm) {
            self.source = source
            self.algorithm = algorithm
        }

        // MARK: - Internal methods

        package func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(sourceIterator: source.makeAsyncIterator(), algorithm: algorithm)
        }
    }
}
