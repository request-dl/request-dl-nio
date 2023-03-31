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
            _ buffers: [BufferProtocol]
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
            while let next = iterator.next() {
                try await next.get()
            }
        }
    }

    fileprivate static func connect(
        writer: HTTPClient.Body.StreamWriter,
        body: Internals.BodySequence
    ) -> EventLoopFuture<Void> {
        let sequence = Internals.StreamWriterSequence(
            writer: writer,
            body: body
        ).makeIterator()

        guard let first = sequence.next() else {
            Log.failure(
                """
                Creating a RequestBody with an empty BodyContent is potentially \
                risky and may cause unexpected behavior.

                Please ensure that a valid content is provided to the RequestBody \
                to avoid any potential issues.

                If no content is intended for the RequestBody, please consider \
                using a different approach.
                """
            )
        }

        return first.flatMapWithEventLoop {
            consume(iterator: sequence, eventLoop: $1)
        }
    }
}
