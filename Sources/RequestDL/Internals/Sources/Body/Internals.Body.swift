/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient

extension Internals {

    struct Body {

        private let _body: Internals.BodySequence

        init(
            _ size: Int? = nil,
            buffers: [BufferProtocol]
        ) {
            _body = .init(
                buffers: buffers,
                size: size
            )
        }
    }
}

extension Internals.Body {

    func build() -> HTTPClient.Body {
        .stream(length: _body.size) {
            Self.connect(
                writer: $0,
                body: _body
            )
        }
    }
}

extension Internals.Body {

    private static func consume(
        iterator: Internals.StreamWriterSequence.Iterator,
        eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        eventLoop.makeFutureWithTask {
            var iterator = iterator
            while let next = iterator.next() {
                try await next.get()
            }
        }
    }

    fileprivate static func connect(
        writer: HTTPClient.Body.StreamWriter,
        body: Internals.BodySequence
    ) -> EventLoopFuture<Void> {
        guard !body.isEmpty else {
            Internals.Log.failure(.emptyRequestBody())
        }

        var sequence = Internals.StreamWriterSequence(
            writer: writer,
            body: body
        ).makeIterator()

        guard let first = sequence.next() else {
            return writer.write(.byteBuffer(.init()))
        }

        return first.flatMapWithEventLoop {
            consume(iterator: sequence, eventLoop: $1)
        }
    }
}
