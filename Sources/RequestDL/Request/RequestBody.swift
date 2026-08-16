//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import RequestDLInternals

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

    /// - Parameter eventLoop: Hosts the task that drives the body. See ``connect(writer:body:eventLoop:)``.
    func build(eventLoop: EventLoop) -> HTTPClient.Body {
        .stream(length: _body.totalSize) {
            Self.connect(
                writer: $0,
                body: _body,
                eventLoop: eventLoop
            )
        }
    }

    // MARK: - Private static methods

    /// Drives the body into `writer`.
    ///
    /// ## Why the loop is passed in
    ///
    /// `HTTPClient.Body.stream` wants an `EventLoopFuture` back synchronously, and driving the
    /// body needs a `Task`, which needs an `EventLoop` to be bridged into a future. Neither of
    /// the two things in scope can supply one: `StreamWriter` exposes only `write(_:)`, and
    /// `RequestBody` is built before any connection exists.
    ///
    /// Two earlier shapes did not work.
    ///
    /// Pulling the first chunk to reach a loop through the future its write returns made the
    /// whole function `async`, which the synchronous closure above cannot call.
    ///
    /// Opening with a zero length write to reach a loop the same way compiled, and was a no op
    /// on the wire, but it was **not** invisible: `HTTPClientResponseDelegate` reports every
    /// part that goes out, so every upload grew a leading progress event of zero bytes. A
    /// 1023 byte body produced two `UploadStep`s instead of one.
    ///
    /// Both call sites already hold a group, so the loop is simply handed over.
    ///
    /// - Note: An empty body produces no iterations, so it needs no special case.
    private static func connect(
        writer: HTTPClient.Body.StreamWriter,
        body: Internals.BodySequence,
        eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
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
