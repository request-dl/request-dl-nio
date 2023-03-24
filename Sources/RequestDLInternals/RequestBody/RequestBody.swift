/*
 See LICENSE for this package's licensing information.
*/

import NIOCore
import AsyncHTTPClient

public struct RequestBody {

    private let buffers: () -> [BufferProtocol]
    private let size: Int?

    public init<Content: BodyContent>(
        _ size: Int? = nil,
        _ body: Content
    ) {
        self.size = size
        self.buffers = {
            let context = _ContextBody()
            Content.makeBody(body, in: context)
            return context.buffers
        }
    }

    public init<Content: BodyContent>(
        _ size: Int? = nil,
        @RequestBodyBuilder content: () -> Content
    ) {
        self.init(size, content())
    }

    func build() -> HTTPClient.Body {
        let body = BodySequence(
            buffers: buffers(),
            size: size
        )

        return .stream(length: body.size) {
            Self.connect(
                writer: $0,
                body: body
            )
        }
    }
}

import Foundation

extension RequestBody {

    static func consume(
        iterator: StreamWriterSequence.Iterator,
        eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        eventLoop.makeFutureWithTask {
            while let next = iterator.next() {
                try await next.get()
            }
        }
    }

    static func connect(
        writer: HTTPClient.Body.StreamWriter,
        body: BodySequence
    ) -> EventLoopFuture<Void> {
        let sequence = StreamWriterSequence(
            writer: writer,
            body: body
        ).makeIterator()

        guard let first = sequence.next() else {
            fatalError()
        }

        return first.flatMapWithEventLoop {
            consume(iterator: sequence, eventLoop: $1)
        }
    }
}

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

extension StreamWriterSequence {

    class Iterator: IteratorProtocol {

        private let writer: HTTPClient.Body.StreamWriter
        private var iterator: BodySequence.Iterator

        init(
            writer: HTTPClient.Body.StreamWriter,
            iterator: BodySequence.Iterator
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
