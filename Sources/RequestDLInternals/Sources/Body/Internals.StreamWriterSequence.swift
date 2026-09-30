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
            private let gate: Internals.FlowControlWindow?

            // MARK: - Unsafe properties

            private var _iterator: Body.AsyncIterator

            // MARK: - Inits

            package init(
                writer: HTTPClient.Body.StreamWriter,
                iterator: Body.AsyncIterator,
                gate: Internals.FlowControlWindow? = nil
            ) {
                self.writer = writer
                self._iterator = iterator
                self.gate = gate
            }

            // MARK: - Methods

            package mutating func next() async throws -> Element? {
                // Before pulling the next chunk, not before writing one already pulled: a
                // suspension then leaves nothing half-consumed behind it, and resuming carries on
                // with exactly the next byte of the body. Not cancellable on its own, and doesn't
                // need to be: every way the exchange ends releases the gate (see
                // `Internals.TransferControl`), after which the write below fails on a request
                // that is already over.
                if let gate, !gate.isWritable {
                    await gate.waitUntilWritable()
                }

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

        /// Shut while the execution is suspended: see `Internals.TransferControl.gate`. `nil`
        /// streams the body without ever pausing, as before.
        package let gate: Internals.FlowControlWindow?

        // MARK: - Inits

        package init(
            writer: HTTPClient.Body.StreamWriter,
            body: Body,
            gate: Internals.FlowControlWindow? = nil
        ) {
            self.writer = writer
            self.body = body
            self.gate = gate
        }

        // MARK: - Internal methods

        package func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(
                writer: writer,
                iterator: body.makeAsyncIterator(),
                gate: gate
            )
        }
    }
}

#endif
