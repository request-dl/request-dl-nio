/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient

extension Internals {

    struct StreamWriterSequence: Sequence {

        typealias Element = EventLoopFuture<Void>

        let writer: HTTPClient.Body.StreamWriter
        let body: BodySequence

        init(
            writer: HTTPClient.Body.StreamWriter,
            body: BodySequence
        ) {
            self.writer = writer
            self.body = body
        }

        func makeIterator() -> Iterator {
            Iterator(
                writer: writer,
                iterator: body.makeIterator()
            )
        }
    }
}

extension Internals.StreamWriterSequence {

    // TODO: - Remove @unchecked
    // HTTPClient.Body.StreamWriter is @preconcurrency
    struct Iterator: IteratorProtocol, @unchecked Sendable {

        // MARK: - Private properties

        private let lock = Lock()
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
            lock.withLock {
                guard let item = _iterator.next() else {
                    return nil
                }

                return writer.write(.byteBuffer(item))
            }
        }
    }
}
