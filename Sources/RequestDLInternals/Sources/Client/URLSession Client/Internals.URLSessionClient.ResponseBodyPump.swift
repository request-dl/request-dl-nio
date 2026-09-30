//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension Internals.URLSessionClient {

    /// Drains a `URLSession.AsyncBytes` response body into an `Internals.DownloadBuffer`, pausing
    /// whenever the buffer's `Internals.FlowControlWindow` is full.
    ///
    /// This is the `.urlSession` executor's back pressure, the counterpart to
    /// `Internals.ClientResponseReceiver.didReceiveBodyPart(task:_:)` returning a pending future on
    /// the `.nio` path. It works because `URLSession.AsyncBytes` is pull-based all the way down:
    /// Foundation feeds it from CFNetwork through a data-delivery callback that CFNetwork waits on
    /// before delivering (and, once its own read-ahead is full, reading off the socket) any more.
    /// So not pulling from `AsyncBytes` -- which is all waiting on the window here does -- holds
    /// the connection itself back. Measured against a server counting the bytes its kernel
    /// actually accepted: a reader that stops leaves the connection stalled around 4-5 MiB past
    /// what it read, under CPU load and a held-up delegate queue alike, where the
    /// `didReceive data:` delegate this replaced (and `URLSessionTask.suspend()`, tried and rejected
    /// before it) let the whole body through. `InternalsURLSessionClientBackPressureTests` pins
    /// that down.
    ///
    /// The data-delivery callback itself (`URLSession:dataTask:_didReceiveData:completionHandler:`)
    /// is private CFNetwork API, which is exactly why this goes through `AsyncBytes` rather than
    /// implementing it on `TaskDelegate` directly: `AsyncBytes` is the public, supported way to get
    /// its behaviour.
    ///
    /// ## Chunking
    ///
    /// `AsyncBytes` hands out one byte at a time, and says nothing about where CFNetwork's own
    /// deliveries begin or end. Appending to `downloadBuffer` byte by byte would cost a queue
    /// operation per byte; batching into fixed-size blocks instead would hold a slow stream's
    /// bytes back until a block filled, which `readingMode` never asked for. So bytes are handed
    /// on exactly where `Internals.DownloadBuffer` could next emit a chunk -- every `.length(n)`
    /// boundary, or the last byte of a `.separator` -- which is the earliest its reader could see
    /// them anyway, and otherwise at most every `maximumPendingBytes`, which only bounds this
    /// function's own buffer. A `.separator` match can straddle two flushes; `DownloadBuffer`'s
    /// own matcher already carries its state across appends for exactly that reason.
    ///
    /// ## Cost
    ///
    /// Byte-at-a-time is `AsyncBytes`' only public interface, and it is not free: every byte is
    /// an `async` call. Hence one tight loop per reading mode below, writing into raw storage,
    /// rather than a general-purpose accumulator. Measured over loopback: a bare
    /// `for try await _ in bytes` tops out around 1.5-3 GB/s optimized but only ~22 MiB/s in an
    /// unoptimized (`-Onone`, i.e. Debug) build, where nothing gets inlined; this loop alone
    /// manages ~400 MiB/s and ~35 MiB/s respectively. End to end through a `SessionTask`, that
    /// costs nothing measurable at the default `.length(1_024)` in an optimized build (~60 MiB/s
    /// either way, the rest of the pipeline dominates), ~3.7x at `.length(65_536)` (1.4 GB/s ->
    /// ~370 MiB/s), and a lot in Debug builds (28 -> ~10 MiB/s at `.length(1_024)`, 680 -> ~10 MiB/s
    /// at `.length(65_536)`), where the `didReceive data:` path it replaced had no per-byte cost.
    ///
    /// ## Liveness
    ///
    /// Only ever waits right after handing `downloadBuffer` everything it had pending, never while
    /// holding bytes back, so every byte the window counts is one the reader can drain on its own:
    /// the invariant `Internals.FlowControlWindow`'s "Liveness" section asks of every producer.
    /// Anything that ends the exchange without the reader draining the window releases it
    /// instead (see the `SessionTask` seed `executeSessionTask` builds, and the reader's own
    /// flow-control lease on `Internals.AsyncStream`), after which this never waits again.
    ///
    /// The window is also what an `Internals.TransferControl` suspends, so a suspended exchange
    /// parks here, at its next flush, exactly like one whose reader fell behind.
    ///
    /// ## Failure
    ///
    /// Whatever was already pulled when `bytes` throws is still handed to `downloadBuffer` before
    /// the error propagates: those bytes did arrive intact, and a continuation of the download
    /// (see `Internals.RangeResumptionPlan`) starts from the count in `deliveredBytes`, which has
    /// to match what the reader actually got.
    ///
    /// - Parameter deliveredBytes: Incremented by every byte handed to `downloadBuffer`.
    static func pumpResponseBody(
        _ bytes: URLSession.AsyncBytes,
        readingMode: Internals.DownloadStep.ReadingMode,
        into downloadBuffer: Internals.DownloadBuffer,
        flowControl: Internals.FlowControlWindow,
        deliveredBytes: inout Int64
    ) async throws {
        let storage = UnsafeMutablePointer<UInt8>.allocate(capacity: Self.maximumPendingBytes)
        defer { storage.deallocate() }

        var iterator = bytes.makeAsyncIterator()
        var count = 0

        func handOver() {
            downloadBuffer.append(makeBuffer(Data(bytes: storage, count: count)))
            deliveredBytes += Int64(count)
            count = .zero
        }

        func flush() async {
            handOver()

            // After `append`, which charged what it just handed over; the same order
            // `Internals.ClientResponseReceiver` checks the window in.
            if !flowControl.isWritable {
                await flowControl.waitUntilWritable()
            }
        }

        let capacity = maximumPendingBytes

        do {
            switch readingMode {
            case .length(let length) where length > .zero:
                // Counted across flushes: a boundary can fall anywhere relative to `capacity`.
                var untilBoundary = length

                while let byte = try await iterator.next() {
                    storage[count] = byte
                    count &+= 1
                    untilBoundary &-= 1

                    if untilBoundary == .zero {
                        untilBoundary = length
                        await flush()
                    } else if count == capacity {
                        await flush()
                    }
                }

            case .separator(let separator) where !separator.isEmpty:
                // Only the separator's last byte can complete a match, so it is the only one
                // worth flushing on; `Internals.DownloadBuffer` decides whether it actually did.
                let terminator = separator[separator.count - 1]

                while let byte = try await iterator.next() {
                    storage[count] = byte
                    count &+= 1

                    if byte == terminator || count == capacity {
                        await flush()
                    }
                }

            default:
                // A degenerate reading mode (`.length` <= 0, empty `.separator`): no boundary to
                // flush on, only the capacity.
                while let byte = try await iterator.next() {
                    storage[count] = byte
                    count &+= 1

                    if count == capacity {
                        await flush()
                    }
                }
            }
        } catch {
            // Not waiting on the window here: nothing more is coming from this exchange, and
            // whatever ends it next releases or reuses the window anyway.
            if count > .zero {
                handOver()
            }

            throw error
        }

        if count > .zero {
            await flush()
        }
    }

    /// Synchronous, in-memory construction, and deliberately not from an `async` context, where
    /// `Internals.DataBuffer`'s `async` initializer would be picked instead: see
    /// `TaskDelegate.urlSession(_:dataTask:didReceive:)` for why the order of appends must not
    /// depend on it.
    private static func makeBuffer(_ data: Data) -> Internals.DataBuffer {
        let byteURL = Internals.ByteURL()
        byteURL.replace(with: data)
        return Internals.DataBuffer(byteURL)
    }

    /// The most bytes `pumpResponseBody` holds back before a flush regardless of `readingMode`.
    /// Only bounds its own buffer; it has no bearing on what the reader sees, since
    /// `Internals.DownloadBuffer` re-chunks whatever it is given.
    static let maximumPendingBytes = 65_536
}

#endif
