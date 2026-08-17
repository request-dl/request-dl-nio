//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore

extension Internals {

    package struct StreamWriterSequence: Sendable, AsyncSequence {

        package struct AsyncIterator: Sendable, AsyncIteratorProtocol {

            // MARK: - Private properties

            private let writer: HTTPClient.Body.StreamWriter

            // MARK: - Unsafe properties

            private var _iterator: Internals.BodySequence.AsyncIterator

            // MARK: - Inits

            package init(
                writer: HTTPClient.Body.StreamWriter,
                iterator: Internals.BodySequence.AsyncIterator
            ) {
                self.writer = writer
                self._iterator = iterator
            }

            // MARK: - Methods

            package mutating func next() async -> Element? {
                guard let item = await _iterator.next() else {
                    return nil
                }

                return writer.write(.byteBuffer(item))
            }
        }

        package typealias Element = EventLoopFuture<Void>

        // MARK: - Internal properties

        package let writer: HTTPClient.Body.StreamWriter
        package let body: BodySequence

        // MARK: - Inits

        package init(writer: HTTPClient.Body.StreamWriter, body: BodySequence) {
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
