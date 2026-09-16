//
// See LICENSE for this package's licensing information.
//

// Feeds HTTPClient.Body.StreamWriter directly: entirely .nio/.nioTransportServices-only. Only
// reachable via RequestBody.connect(writer:body:eventLoop:), itself NIOCore-gated.
#if canImport(NIOCore)

import AsyncHTTPClient
import NIOCore
import NIOFoundationEssentialsCompat

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension Internals {

    /// Generic over `Body`, rather than hardwired to `Internals.BodySequence`, so it can
    /// drive either a fixed, known-length body or a `Internals.CompressingByteSequence` (whose
    /// final size, and whose ability to fail mid-stream if a custom `Compressor` throws, are both
    /// only known once the whole thing has been pulled through).
    ///
    /// `Body.Element` is `Data`, matching the public `RequestBody`'s own currency, this type is
    /// the one place that actually needs a `ByteBuffer` (`HTTPClient.Body.StreamWriter` wants
    /// one), so the conversion happens right here, once per chunk, rather than forcing NIO onto
    /// `RequestBody`'s public surface.
    package struct StreamWriterSequence<Body: AsyncSequence & Sendable>: Sendable, AsyncSequence
    where Body.Element == Data {

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

                return writer.write(.byteBuffer(ByteBuffer(data: item)))
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
