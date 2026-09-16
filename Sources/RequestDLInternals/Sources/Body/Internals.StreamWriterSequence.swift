//
// See LICENSE for this package's licensing information.
//

// Feeds HTTPClient.Body.StreamWriter directly: entirely .nio/.nioTransportServices-only. Only
// reachable via RequestBody.connect(writer:body:eventLoop:), itself NIOCore-gated.
#if canImport(NIOCore)

import AsyncHTTPClient
import NIOCore

extension Internals {

    /// Generic over `Body`, rather than hardwired to `Internals.BodySequence`, so it can
    /// drive either a fixed, known-length body or a `Internals.CompressingByteSequence` (whose
    /// final size, and whose ability to fail mid-stream if a custom `Compressor` throws, are both
    /// only known once the whole thing has been pulled through).
    ///
    /// `Body.Element` is `Internals.Bytes`, not the public `RequestBody`'s own `Data` currency:
    /// this is fed from `RequestBody.bytesSequence`, not `RequestBody` itself, specifically so a
    /// chunk that started life as a `NIOCore.ByteBuffer` (a file read, say) reaches
    /// `HTTPClient.Body.StreamWriter` via `asByteBuffer()`'s cached, zero-copy path instead of
    /// paying a `ByteBuffer` -> `Data` -> `ByteBuffer` round trip through `RequestBody`'s public,
    /// `Data`-typed `AsyncSequence` conformance.
    package struct StreamWriterSequence<Body: AsyncSequence & Sendable>: Sendable, AsyncSequence
    where Body.Element == Internals.Bytes {

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
                guard var item = try await _iterator.next() else {
                    return nil
                }

                return writer.write(.byteBuffer(item.asByteBuffer()))
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

#endif
