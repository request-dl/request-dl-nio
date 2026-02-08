/*
 See LICENSE for this package's licensing information.
 */

import Foundation
import NIOCore
import AsyncHTTPClient

/**
 A structure representing the body of an HTTP request.
 This type encapsulates the data and settings for the request body,
 such as its size and chunking strategy.
 */
public struct RequestBody: Sendable {

    // MARK: - Public properties

    /// The size of each chunk used for streaming the body data.
    public var chunkSize: Int {
        _body.chunkSize
    }

    /// The total size of the body data in bytes.
    public var totalSize: Int {
        _body.totalSize
    }

    // MARK: - Private properties

    private let _body: Internals.BodySequence

    // MARK: - Inits

    init(
        chunkSize: Int? = nil,
        buffers: [Internals.AnyBuffer]
    ) {
        _body = .init(
            chunkSize: chunkSize,
            buffers: buffers
        )
    }

    // MARK: - Internal methods

    func build() -> HTTPClient.Body {
        .stream(length: _body.totalSize) {
            Self.connect(
                writer: $0,
                body: _body
            )
        }
    }

    // MARK: - Private static methods

    private static func connect(
        writer: HTTPClient.Body.StreamWriter,
        body: Internals.BodySequence
    ) -> EventLoopFuture<Void> {
        guard !body.isEmpty else {
            return writer.write(.byteBuffer(.init()))
        }

        var sequence = Internals.StreamWriterSequence(
            writer: writer,
            body: body
        ).makeIterator()

        guard let first = sequence.next() else {
            return writer.write(.byteBuffer(.init()))
        }

        return first.flatMapWithEventLoop { [sequence] in
            consume(iterator: sequence, eventLoop: $1)
        }
    }

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
}

extension RequestBody: Sequence {

    /**
     An iterator for traversing the `RequestBody`'s underlying buffer sequence.
     This allows the body to be treated as a sequence of `ByteBuffer` chunks.
     */
    public struct Iterator: IteratorProtocol {

        fileprivate var iterator: Internals.BodySequence.Iterator

        /**
         Advances to the next element in the sequence of buffer chunks.

         - Returns: The next `ByteBuffer` in the sequence, or `nil` if there are no more elements.
         */
        public mutating func next() -> NIOCore.ByteBuffer? {
            iterator.next()
        }
    }

    /**
     Creates an iterator over the buffer chunks in this request body.

     - Returns: An instance of `RequestBody.Iterator`.
     */
    public func makeIterator() -> Iterator {
        Iterator(iterator: _body.makeIterator())
    }
}
