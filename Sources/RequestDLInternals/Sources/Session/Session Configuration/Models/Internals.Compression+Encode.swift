//
// See LICENSE for this package's licensing information.
//

// `Internals.NIOHTTPCompressorStream` drives `NIOHTTPRequestCompressor` directly, so this whole
// file is NIO-only: there's no portable equivalent here the way `Internals.PrivateKey`/
// `Internals.Certificate` have one. `PortableGzipCompressorStream`/`PortableDeflateCompressorStream`
// (in the `RequestDL` module) are what stand in for it when NIOCore isn't available.
#if canImport(NIOCore)

import Dispatch
import NIOConcurrencyHelpers
import NIOCore
import NIOEmbedded
import NIOHTTP1
import NIOHTTPCompression
import NIOPosix

extension Internals.Compression.Algorithm {

    /// The wire name this algorithm's `Content-Encoding` value takes: `NIOCompression
    /// .Algorithm`'s own `description`, so this always matches whatever `NIOHTTPRequestCompressor`
    /// itself would have written into the header.
    package var contentEncodingValue: String {
        build().description
    }
}

extension Internals {

    /// Compresses through the same codec `NIOHTTPRequestCompressor` applies on the wire for the
    /// `.nio` executor, driven through a persistent `EmbeddedChannel` rather than a live
    /// connection pipeline, so it can be fed incrementally, one `callAsFunction(compressing:)`
    /// call per chunk, across the lifetime of a single request. Reusing the handler itself
    /// (rather than binding `CNIOExtrasZlib` directly, which isn't a public product of
    /// `swift-nio-extras`) keeps this byte-for-byte identical to what the live pipeline produces.
    ///
    /// - Important: `EmbeddedChannel` requires every call to happen on the OS thread that created
    /// it, but this type is driven from `Internals.CompressingByteSequence.AsyncIterator.next()`,
    /// which resumes on whatever thread Swift Concurrency picks. Every touch of `channel` is
    /// therefore routed through `worker`, an OS thread this stream starts for itself.
    ///
    /// `worker` is a plain thread, not an `EventLoop`, and the caller waits for it on a
    /// semaphore, not on an `EventLoopFuture`: `wait()` is a precondition failure, in release
    /// builds too, on any thread that belongs to an event loop group, which is where an app that
    /// installs NIO as Swift Concurrency's global executor runs this code. A thread of the
    /// stream's own never waits for anyone, so two streams cannot wait for each other either.
    /// `CompressorStream` is a synchronous protocol, so the caller blocks, for the
    /// microseconds one zlib call takes.
    ///
    /// - Important: `EmbeddedChannel` also asserts its creating thread in `deinit`. `finish()`
    /// is ordinarily the last thing that happens to a stream and nils out `Box.channel` from a
    /// job on `worker`. If a request is cancelled or fails mid-upload, `finish()` may never run,
    /// and `Box.deinit` guards that path: it moves the remaining reference into an `Unmanaged`
    /// handle and releases it from a job on `worker`, without waiting for it, so the channel is
    /// always deallocated on the thread that created it.
    package struct NIOHTTPCompressorStream: Internals.CompressorStream {

        /// `@unchecked`: `channel` is only ever read or mutated from inside a job run by
        /// `worker`, i.e. always serialized onto that single thread; see the type's own doc
        /// comment for why that invariant matters here specifically.
        private final class Box: @unchecked Sendable {

            // MARK: - Internal properties

            let worker: Worker
            var channel: EmbeddedChannel?

            // MARK: - Inits

            init(worker: Worker, channel: EmbeddedChannel) {
                self.worker = worker
                self.channel = channel
            }

            deinit {
                // `handle` is built inside this `if let` (rather than a function-scope `guard
                // let`) so `channel`'s local, unwrapped binding goes out of scope, releasing
                // its own reference, right here, before the job below ever runs. That leaves the
                // `Unmanaged` retain as the *only* remaining reference, so releasing it on
                // `worker`'s thread is what actually triggers deallocation.
                //
                // A function-scope binding would instead stay alive until `deinit` itself
                // returns, releasing its own reference back on whatever thread triggered this
                // deinit in the first place: silently reintroducing the exact bug this exists
                // to avoid.
                var handle: UnmanagedChannelHandle?

                if let channel {
                    self.channel = nil
                    handle = UnmanagedChannelHandle(pointer: Unmanaged.passRetained(channel).toOpaque())
                }

                guard let handle else {
                    worker.stop()
                    return
                }

                worker.stop(after: {
                    Unmanaged<EmbeddedChannel>.fromOpaque(handle.pointer).release()
                })
            }
        }

        /// A thread of its own that runs the jobs handed to it one at a time, in order, and ends
        /// once it is stopped: a `NIOThreadPool` of one thread, which is not an `EventLoop`, on
        /// purpose (see the doc comment of the enclosing type). Not Foundation's `Thread`, which
        /// would link `libFoundation` on Linux.
        private final class Worker: @unchecked Sendable {

            // MARK: - Private properties

            private let pool = NIOThreadPool(numberOfThreads: 1)
            private let lock = NIOLock()
            private var isStopped = false
            private var hasExited = false

            // MARK: - Internal properties

            var isRunning: Bool {
                lock.withLock { !hasExited }
            }

            // MARK: - Inits

            init() {
                pool.start()
            }

            // MARK: - Internal methods

            /// Runs `body` on the thread and returns what it returned, blocking the caller until
            /// then.
            ///
            /// - Throws: `ChannelAlreadyFinishedError` if the worker was already stopped, which
            /// is a call after `finish()`; otherwise whatever `body` threw.
            func perform<Output: Sendable>(_ body: @escaping @Sendable () throws -> Output) throws -> Output {
                guard lock.withLock({ !isStopped }) else {
                    throw ChannelAlreadyFinishedError()
                }

                let slot = Slot<Output>()
                let done = DispatchSemaphore(value: 0)

                // A job the pool drops (it shut down meanwhile) is still called, as cancelled,
                // so the caller is always released.
                pool.submit { state in
                    if case .active = state {
                        slot.result = Result { try body() }
                    }

                    done.signal()
                }

                done.wait()

                guard let result = slot.result else {
                    throw ChannelAlreadyFinishedError()
                }

                return try result.get()
            }

            /// Ends the thread once the jobs already queued, and then `last`, have run. Does not
            /// wait for any of it.
            ///
            /// `last` is queued as a job instead of run after the shutdown because the pool
            /// cancels what is still queued when it shuts down, and `last` has to run on the
            /// thread.
            func stop(after last: (@Sendable () -> Void)? = nil) {
                let isFirst = lock.withLock {
                    defer { isStopped = true }
                    return !isStopped
                }

                guard isFirst else {
                    return
                }

                pool.submit { [self] state in
                    if case .active = state {
                        last?()
                    }

                    pool.shutdownGracefully(queue: .global()) { [self] _ in
                        lock.withLock { hasExited = true }
                    }
                }
            }
        }

        /// Where a job leaves its result for the caller waiting on the semaphore. Written before
        /// the signal and read after the wait, which orders the two.
        private final class Slot<Output: Sendable>: @unchecked Sendable {
            var result: Result<Output, any Error>?
        }

        /// Thrown by `callAsFunction(compressing:)`/`finish()` if `box.channel` is already `nil`:
        /// reachable only if one of them is called again after `finish()` already ran, which
        /// violates `CompressorStream`'s contract (a single `finish()`, last). Guards the caller
        /// mistake without a force unwrap, rather than asserting it can never happen.
        private struct ChannelAlreadyFinishedError: Error {}

        /// Wraps the raw pointer `Box.deinit` hands across to `worker`:
        /// `UnsafeMutableRawPointer` itself isn't `Sendable` (pointers don't promise anything
        /// about what they point to), but this one is safe to move: it's a manually-retained
        /// (`Unmanaged.passRetained`) reference nothing else holds or touches concurrently, and
        /// the job that receives it is the sole, one-time consumer that releases it.
        private struct UnmanagedChannelHandle: @unchecked Sendable {
            let pointer: UnsafeMutableRawPointer
        }

        // MARK: - Private properties

        private let box: Box

        // MARK: - Inits

        package init(algorithm: Internals.Compression.Algorithm) throws {
            let worker = Worker()
            let encoding = algorithm.build()

            do {
                let channel = try worker.perform {
                    let channel = EmbeddedChannel()
                    try channel.pipeline.syncOperations.addHandler(
                        NIOHTTPRequestCompressor(encoding: encoding)
                    )

                    let head = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/")
                    try channel.writeOutbound(HTTPClientRequestPart.head(head))
                    return UncheckedChannel(channel)
                }

                box = Box(worker: worker, channel: channel.channel)
            } catch {
                worker.stop()
                throw error
            }
        }

        // MARK: - Internal properties

        /// Whether the thread this stream runs on is still alive, read through a closure that
        /// does not keep the stream itself alive. What a test uses to tell that a finished or
        /// dropped stream gave its thread back.
        package var workerProbe: @Sendable () -> Bool {
            let worker = box.worker
            return { worker.isRunning }
        }

        // MARK: - Internal methods

        package func callAsFunction(compressing bytes: Internals.Bytes) throws -> Internals.Bytes {
            var bytes = bytes
            let buffer = bytes.asByteBuffer()

            // Jobs hold the box `unowned(unsafe)`: this call holds it until the job is done, and
            // a job holding the last reference would release it on the worker thread.
            return try box.worker.perform { [unowned(unsafe) box] in
                guard let channel = box.channel else {
                    throw ChannelAlreadyFinishedError()
                }

                try channel.writeOutbound(HTTPClientRequestPart.body(.byteBuffer(buffer)))
                return Internals.Bytes(try Self.drain(channel))
            }
        }

        package func finish() throws -> Internals.Bytes {
            let result = try box.worker.perform { [unowned(unsafe) box] in
                guard let channel = box.channel else {
                    throw ChannelAlreadyFinishedError()
                }

                try channel.writeOutbound(HTTPClientRequestPart.end(nil))
                let result = try Self.drain(channel)
                _ = try? channel.finish()

                // Drops the stored reference here, on `worker`'s own thread, rather than
                // leaving it for whenever/wherever this value's box eventually gets deallocated;
                // see the type's own doc comment.
                box.channel = nil
                return Internals.Bytes(result)
            }

            // Nothing is left for the thread to do: a second call is the caller's mistake and
            // gets `ChannelAlreadyFinishedError` instead of waiting on a thread nobody needs.
            box.worker.stop()
            return result
        }

        // MARK: - Private methods

        /// Collects every outbound chunk `NIOHTTPRequestCompressor` produced into one contiguous
        /// `ByteBuffer`. Handed back as is, not as `Data`: the caller wraps it into an
        /// `Internals.Bytes` that stays `ByteBuffer`-backed until something downstream actually
        /// asks for `Data`, rather than converting here on the chance it might.
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

    /// Carries the freshly created channel from `worker`'s thread back to `init`. After this
    /// the channel is only touched from `worker` again, through `Box`.
    private struct UncheckedChannel: @unchecked Sendable {

        let channel: EmbeddedChannel

        init(_ channel: EmbeddedChannel) {
            self.channel = channel
        }
    }
}

#endif
