/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
@preconcurrency import AsyncHTTPClient

extension Internals {

    struct StreamWriterSequence: Sendable, Sequence {

        struct Iterator: Sendable, IteratorProtocol {

            // MARK: - Private properties

            private let writer: HTTPClient.Body.StreamWriter

            // MARK: - Unsafe properties

            private var _iterator: Internals.BodySequence.Iterator

            // MARK: - Inits

            init(
                writer: HTTPClient.Body.StreamWriter,
                iterator: Internals.BodySequence.Iterator
            ) {
                self.writer = writer
                self._iterator = iterator
            }

            // MARK: - Methods

            mutating func next() -> Element? {
                guard let item = _iterator.next() else {
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

        func makeIterator() -> Iterator {
            Iterator(
                writer: writer,
                iterator: body.makeIterator()
            )
        }
    }
}
