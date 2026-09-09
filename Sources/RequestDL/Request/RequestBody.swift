//
// See LICENSE for this package's licensing information.
//

import AsyncHTTPClient
import NIOCore
import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

/// A structure representing the body of an HTTP request.
/// This type encapsulates the data and settings for the request body,
/// such as its size and chunking strategy.
public struct RequestBody: Sendable {

    /// Which known list of buffers backs this body, versus which one is compressed on the fly as
    /// the transport pulls from it. Kept as an enum on `RequestBody` itself, not a wrapper type,
    /// so every existing `RequestBody`-typed call site (`RequestConfiguration.body`, `Payload`/
    /// `Form` construction) keeps working unchanged regardless of which backing a given instance
    /// actually has.
    private enum Backing: Sendable {
        case fixed(Internals.BodySequence)
        case compressing(Internals.CompressingByteSequence<Internals.BodySequence>)
    }

    // MARK: - Public properties

    /// The size of each chunk used for streaming the body data. `.zero` for a compressing body --
    /// chunking is the compressor's own business there, not a fixed size decided upfront.
    public var chunkSize: Int {
        switch backing {
        case .fixed(let body):
            return body.chunkSize
        case .compressing:
            return .zero
        }
    }

    /// The total size of the body data in bytes.
    ///
    /// - Important: For a compressing body, this reports the *original*, pre-compression size --
    /// a best-effort upper-bound progress estimate, not the actual wire size, which isn't known
    /// until the whole body has streamed through. A progress reader dividing by this value sees
    /// its percentage approach completion a little before the upload actually finishes, rather
    /// than dividing by an unknown value or a stale zero.
    public var totalSize: Int {
        switch backing {
        case .fixed(let body):
            return body.totalSize
        case .compressing(let sequence):
            return sequence.source.totalSize
        }
    }

    /// The file this body already lives in, when nothing but reading it directly would be
    /// needed to reproduce it exactly -- see `Internals.BodySequence.wholeFileURL`. Not public:
    /// this exists for `Internals.URLSessionClient+RequestExecutingClient.swift` to skip a
    /// redundant copy for a `Payload(url:)`-only body, not as API surface for callers of
    /// `RequestBody` itself.
    ///
    /// Always `nil` for a compressing body: uploading straight from the original file would skip
    /// compression entirely, which defeats the point of configuring it.
    var wholeFileURL: URL? {
        switch backing {
        case .fixed(let body):
            return body.wholeFileURL
        case .compressing:
            return nil
        }
    }

    /// The size to declare on the wire -- `nil` switches both executors to unknown-length,
    /// chunked-transfer upload. Distinct from the public ``totalSize``, which for a compressing
    /// body reports the *original* size as a progress estimate, never the (not-yet-known) wire
    /// size a `Content-Length`/declared-length upload would need to be exactly right.
    var knownWireSize: Int? {
        switch backing {
        case .fixed(let body):
            return body.totalSize
        case .compressing:
            return nil
        }
    }

    // MARK: - Private properties

    private let backing: Backing

    // MARK: - Inits

    init(
        chunkSize: Int? = nil,
        buffers: [Internals.AnyBuffer]
    ) {
        backing = .fixed(
            Internals.BodySequence(
                chunkSize: chunkSize,
                buffers: buffers
            )
        )
    }

    private init(backing: Backing) {
        self.backing = backing
    }

    // MARK: - Internal methods

    /// Wraps this body so each chunk is compressed as it's pulled by the transport -- see
    /// `Internals.CompressingByteSequence`'s own doc comment for why that's worth doing over
    /// draining the whole body into memory before compression starts.
    func compressed(with algorithm: any Internals.CompressionAlgorithm) -> RequestBody {
        switch backing {
        case .fixed(let body):
            return RequestBody(backing: .compressing(.init(source: body, algorithm: algorithm)))
        case .compressing:
            // `RequestConfiguration.applyCompression()` only ever calls this once, on a freshly
            // assembled body -- reached only if some future caller compresses twice.
            return self
        }
    }

    /// - Parameter eventLoop: Hosts the task that streams the body, when there is one. See
    /// ``connect(writer:body:eventLoop:)``.
    func build(eventLoop: EventLoop) -> HTTPClient.Body {
        .stream(length: knownWireSize) {
            Self.connect(
                writer: $0,
                body: self,
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
        body: RequestBody,
        eventLoop: EventLoop
    ) -> EventLoopFuture<Void> {
        eventLoop.makeFutureWithTask {
            var iterator = Internals.StreamWriterSequence(
                writer: writer,
                body: body
            ).makeAsyncIterator()

            while let next = try await iterator.next() {
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

        fileprivate enum Backing {
            case fixed(Internals.BodySequence.AsyncIterator)
            case compressing(Internals.CompressingByteSequence<Internals.BodySequence>.AsyncIterator)
        }

        fileprivate var backing: Backing

        ///
        /// Advances to the next element in the sequence of buffer chunks.
        ///
        /// - Returns: The next `ByteBuffer` in the sequence, or `nil` if there are no more elements.
        /// - Throws: Whatever a configured ``Compressor``'s ``CompressorStream`` throws, for a
        /// compressing body -- a fixed body never throws, but shares this signature so callers
        /// don't need to know which kind of `RequestBody` they were handed.
        ///
        public mutating func next() async throws -> NIOCore.ByteBuffer? {
            switch backing {
            case .fixed(var iterator):
                let element = await iterator.next()
                backing = .fixed(iterator)
                return element

            case .compressing(var iterator):
                let element = try await iterator.next()
                backing = .compressing(iterator)
                return element
            }
        }
    }

    ///
    /// Creates an iterator over the buffer chunks in this request body.
    ///
    /// - Returns: An instance of `RequestBody.Iterator`.
    ///
    public func makeAsyncIterator() -> AsyncIterator {
        switch backing {
        case .fixed(let body):
            return AsyncIterator(backing: .fixed(body.makeAsyncIterator()))
        case .compressing(let sequence):
            return AsyncIterator(backing: .compressing(sequence.makeAsyncIterator()))
        }
    }
}
