//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore

/// A structure representing the body of an HTTP request.
/// This type encapsulates the data and settings for the request body,
/// such as its size and chunking strategy.
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

    /// Drives the body into `writer`.
    ///
    /// ## Why it opens with an empty write
    ///
    /// `HTTPClient.Body.stream` wants an `EventLoopFuture` back synchronously, and driving the
    /// body needs a `Task`, which needs an `EventLoop` to be bridged back into a future.
    /// Nothing here owns one: `StreamWriter` exposes only `write(_:)`, and `RequestBody` is
    /// built long before any loop is picked. The future a write returns is the sole handle on
    /// one, so the first write is what reaches it.
    ///
    /// The previous version got there by pulling the first chunk instead, which made the whole
    /// function `async` and left it uncallable from the synchronous closure above. That is also
    /// why the empty-body case had its own branch: the pull could come back with nothing.
    ///
    /// - Important: The empty write is a no op on the wire. The body is always sent with a
    /// known `length`, so `Content-Length` framing is used rather than chunked, where a zero
    /// length write would instead be the terminator.
    private static func connect(
        writer: HTTPClient.Body.StreamWriter,
        body: Internals.BodySequence
    ) -> EventLoopFuture<Void> {
        writer.write(.byteBuffer(.init())).flatMapWithEventLoop { _, eventLoop in
            // An empty body simply produces no iterations, so it needs no special case.
            eventLoop.makeFutureWithTask {
                var iterator = Internals.StreamWriterSequence(
                    writer: writer,
                    body: body
                ).makeAsyncIterator()

                while let next = await iterator.next() {
                    try await next.get()
                }
            }
        }
    }
}

extension RequestBody: AsyncSequence {

    ///
    /// An iterator for traversing the `RequestBody`'s underlying buffer sequence.
    /// This allows the body to be treated as a sequence of `ByteBuffer` chunks.
    ///
    public struct AsyncIterator: AsyncIteratorProtocol {

        fileprivate var iterator: Internals.BodySequence.AsyncIterator

        ///
        /// Advances to the next element in the sequence of buffer chunks.
        ///
        /// - Returns: The next `ByteBuffer` in the sequence, or `nil` if there are no more elements.
        ///
        public mutating func next() async -> NIOCore.ByteBuffer? {
            await iterator.next()
        }
    }

    ///
    /// Creates an iterator over the buffer chunks in this request body.
    ///
    /// - Returns: An instance of `RequestBody.Iterator`.
    ///
    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: _body.makeAsyncIterator())
    }
}
