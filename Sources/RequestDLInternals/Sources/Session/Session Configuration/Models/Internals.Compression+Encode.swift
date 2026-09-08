//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOEmbedded
import NIOHTTP1
import NIOHTTPCompression
import NIOPosix

extension Internals.Compression.Algorithm {

    /// The wire name this algorithm's `Content-Encoding` value takes -- `NIOCompression
    /// .Algorithm`'s own `description`, so this always matches whatever `NIOHTTPRequestCompressor`
    /// itself would have written into the header.
    package var contentEncodingValue: String {
        build().description
    }
}

extension Internals {

    /// Compresses through the same codec `NIOHTTPRequestCompressor` applies on the wire for the
    /// `.nio` executor -- driven through a persistent `EmbeddedChannel` rather than a live
    /// connection pipeline, so it can be fed incrementally, one `callAsFunction(compressing:)`
    /// call per chunk, across the lifetime of a single request, rather than only in one big
    /// write-all/read-all round trip.
    ///
    /// Reusing the handler itself -- rather than binding `CNIOExtrasZlib` directly, which isn't a
    /// public product of `swift-nio-extras` -- keeps this byte-for-byte identical to what
    /// `NIOHTTPRequestCompressor` running in a live connection pipeline would produce.
    ///
    /// - Important: `EmbeddedChannel`/`EmbeddedEventLoop` require every call to happen on the
    /// exact OS thread that created them. This type is driven from
    /// `Internals.CompressingByteSequence.AsyncIterator.next()`, which resumes after each `await
    /// sourceIterator.next()` on whatever thread Swift Concurrency's
    /// cooperative pool happens to pick, not necessarily the one that created this stream. Every
    /// touch of `channel` is therefore routed through `eventLoop` -- one real, persistent-thread
    /// loop captured once at `init` -- so `channel` is always created and always operated on that
    /// same single thread no matter which thread `callAsFunction`/`finish` themselves get called
    /// from. `CompressorStream` is a synchronous protocol (mirroring the public, sync-by-design
    /// `RequestDL.CompressorStream`), so this hops over with a blocking `.wait()` rather than
    /// `async`/`await` -- safe here because `eventLoop` is backed by a genuine OS thread entirely
    /// outside Swift Concurrency's cooperative pool, and each call is a microsecond-scale zlib
    /// operation, not a real wait.
    ///
    /// - Important: Thread affinity isn't only a concern for the calls above -- `EmbeddedChannel`
    /// itself does real work in `deinit` (resolving its close promise), which also asserts the
    /// creating thread. Ordinarily `finish()` is always the last thing that happens to a stream
    /// (see `Internals.CompressingByteSequence.AsyncIterator.next()`), and it already nils out
    /// `Box.channel` from within its own `eventLoop.submit`, so the *stored* reference is gone
    /// before this value (or the existential box wrapping it) is ever deallocated off-thread. But
    /// if a request is cancelled or fails mid-upload, `finish()` may never run, and ARC then drops
    /// the last reference to `Box` -- and transitively to `channel` -- from whatever thread
    /// happens to release it. `Box.deinit` guards that path: it moves the one remaining reference
    /// into an `Unmanaged` handle (invisible to ARC's automatic, scope-exit release) and only
    /// releases it from inside `eventLoop.submit`, so the *actual* deallocation -- wherever it's
    /// triggered from -- always lands on the thread `channel` was created on.
    package struct NIOHTTPCompressorStream: Internals.CompressorStream {

        /// `@unchecked` -- `channel` is only ever read or mutated from inside a closure submitted
        /// to `eventLoop`, i.e. always serialized onto that single thread; see the type's own doc
        /// comment for why that invariant matters here specifically.
        private final class Box: @unchecked Sendable {

            // MARK: - Internal properties

            let eventLoop: EventLoop
            var channel: EmbeddedChannel?

            // MARK: - Inits

            init(eventLoop: EventLoop, channel: EmbeddedChannel) {
                self.eventLoop = eventLoop
                self.channel = channel
            }

            deinit {
                guard channel != nil else {
                    return
                }

                guard !eventLoop.inEventLoop else {
                    channel = nil
                    return
                }

                let handle: UnmanagedChannelHandle
                do {
                    let channel = channel!
                    self.channel = nil
                    handle = UnmanagedChannelHandle(pointer: Unmanaged.passRetained(channel).toOpaque())
                }

                try? eventLoop.submit {
                    Unmanaged<EmbeddedChannel>.fromOpaque(handle.pointer).release()
                }.wait()
            }
        }

        /// Wraps the raw pointer `Box.deinit` hands across the `eventLoop.submit` boundary --
        /// `UnsafeMutableRawPointer` itself isn't `Sendable` (pointers don't promise anything
        /// about what they point to), but this one is safe to move: it's a manually-retained
        /// (`Unmanaged.passRetained`) reference nothing else holds or touches concurrently, and
        /// the closure that receives it is the sole, one-time consumer that releases it.
        private struct UnmanagedChannelHandle: @unchecked Sendable {
            let pointer: UnsafeMutableRawPointer
        }

        // MARK: - Private properties

        private let box: Box

        // MARK: - Inits

        package init(algorithm: Internals.Compression.Algorithm) throws {
            let eventLoop = NIOSingletons.posixEventLoopGroup.next()

            let channel = try eventLoop.submit {
                let channel = EmbeddedChannel()
                try channel.pipeline.syncOperations.addHandler(
                    NIOHTTPRequestCompressor(encoding: algorithm.build())
                )

                let head = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/")
                try channel.writeOutbound(HTTPClientRequestPart.head(head))
                return channel
            }.wait()

            box = Box(eventLoop: eventLoop, channel: channel)
        }

        // MARK: - Internal methods

        package func callAsFunction(compressing bytes: ByteBuffer) throws -> ByteBuffer {
            try box.eventLoop.submit { [box] in
                let channel = box.channel!
                try channel.writeOutbound(HTTPClientRequestPart.body(.byteBuffer(bytes)))
                return try Self.drain(channel)
            }.wait()
        }

        package func finish() throws -> ByteBuffer {
            try box.eventLoop.submit { [box] in
                let channel = box.channel!
                try channel.writeOutbound(HTTPClientRequestPart.end(nil))
                let result = try Self.drain(channel)
                _ = try? channel.finish()

                // Drops the stored reference here, on `eventLoop`'s own thread, rather than
                // leaving it for whenever/wherever this value's box eventually gets deallocated --
                // see the type's own doc comment.
                box.channel = nil
                return result
            }.wait()
        }

        // MARK: - Private methods

        private static func drain(_ channel: EmbeddedChannel) throws -> ByteBuffer {
            var output = channel.allocator.buffer(capacity: .zero)

            while let part = try channel.readOutbound(as: HTTPClientRequestPart.self) {
                guard case .body(.byteBuffer(var chunk)) = part else {
                    continue
                }

                output.writeBuffer(&chunk)
            }

            return output
        }
    }
}
