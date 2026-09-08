//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore

extension Internals {

    /// Generic over `Body` -- rather than hardwired to `Internals.BodySequence` -- so it can
    /// drive either a fixed, known-length body or a `Internals.CompressingByteSequence` (whose
    /// final size, and whose ability to fail mid-stream if a custom `Compressor` throws, are both
    /// only known once the whole thing has been pulled through).
    package struct StreamWriterSequence<Body: AsyncSequence & Sendable>: Sendable, AsyncSequence
    where Body.Element == ByteBuffer {

        package struct AsyncIterator: AsyncIteratorProtocol {

            // MARK: - Private properties

            private let writer: HTTPClient.Body.StreamWriter

            // MARK: - Unsafe properties

            private var _iterator: Body.AsyncIterator

            // MARK: - Inits

            package init(
                writer: HTTPClient.Body.StreamWriter,
                iterator: Body.AsyncIterator
            ) {
                self.writer = writer
                self._iterator = iterator
            }

            // MARK: - Methods

            package mutating func next() async throws -> Element? {
                guard let item = try await _iterator.next() else {
                    return nil
                }

                return writer.write(.byteBuffer(item))
            }
        }

        package typealias Element = EventLoopFuture<Void>

        // MARK: - Internal properties

        package let writer: HTTPClient.Body.StreamWriter
        package let body: Body

        // MARK: - Inits

        package init(writer: HTTPClient.Body.StreamWriter, body: Body) {
            self.writer = writer
            self.body = body
        }

        // MARK: - Internal methods

        package func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(
                writer: writer,
                iterator: body.makeAsyncIterator()
            )
        }
    }
}
