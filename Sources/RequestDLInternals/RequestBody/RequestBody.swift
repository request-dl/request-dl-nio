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

    func build(_ eventLoop: EventLoop) -> HTTPClient.Body {
        let iterator = BodySequence(
            buffers: buffers(),
            size: size
        ).makeIterator()

        return .stream(length: iterator.size) { stream in
            write(
                iterator: iterator,
                stream: stream,
                eventLoop: eventLoop
            )
        }
    }
}

extension RequestBody {

    func write(
        iterator: BodySequence.Iterator,
        stream: HTTPClient.Body.StreamWriter,
        eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        guard let item = iterator.next() else {
            return eventLoop.makeSucceededVoidFuture()
        }

        return stream.write(.byteBuffer(item)).flatMap {
            write(
                iterator: iterator,
                stream: stream,
                eventLoop: eventLoop
            )
        }
    }
}
