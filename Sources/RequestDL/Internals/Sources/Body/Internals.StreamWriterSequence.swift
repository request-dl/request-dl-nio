//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore

extension Internals {

    struct StreamWriterSequence: Sendable, AsyncSequence {

        struct AsyncIterator: Sendable, AsyncIteratorProtocol {

            // MARK: - Private properties

            private let writer: HTTPClient.Body.StreamWriter

            // MARK: - Unsafe properties

            private var _iterator: Internals.BodySequence.AsyncIterator

            // MARK: - Inits

            init(
                writer: HTTPClient.Body.StreamWriter,
                iterator: Internals.BodySequence.AsyncIterator
            ) {
                self.writer = writer
                self._iterator = iterator
            }

            // MARK: - Methods

            mutating func next() async -> Element? {
                guard let item = await _iterator.next() else {
                    return nil
                }

                return writer.write(.byteBuffer(item))
            }
        }

        typealias Element = EventLoopFuture<Void>

        // MARK: - Internal properties

        let writer: HTTPClient.Body.StreamWriter
        let body: BodySequence

        // MARK: - Internal methods

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(
                writer: writer,
                iterator: body.makeAsyncIterator()
            )
        }
    }
}
