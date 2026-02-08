/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import NIOCore
import AsyncHTTPClient

public struct RequestBody: Sendable {

    // MARK: - Public properties

    public var chunkSize: Int {
        _body.chunkSize
    }

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

    public struct Iterator: IteratorProtocol {

        fileprivate var iterator: Internals.BodySequence.Iterator

        public mutating func next() -> NIOCore.ByteBuffer? {
            iterator.next()
        }
    }

    public func makeIterator() -> Iterator {
        Iterator(iterator: _body.makeIterator())
    }
}
