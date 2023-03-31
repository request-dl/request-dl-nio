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

    class Iterator: IteratorProtocol {

        private let writer: HTTPClient.Body.StreamWriter
        private var iterator: Internals.BodySequence.Iterator

        init(
            writer: HTTPClient.Body.StreamWriter,
            iterator: Internals.BodySequence.Iterator
        ) {
            self.writer = writer
            self.iterator = iterator
        }

        func next() -> Element? {
            guard let item = iterator.next() else {
                return nil
            }

            return writer.write(.byteBuffer(item))
        }
    }
}
