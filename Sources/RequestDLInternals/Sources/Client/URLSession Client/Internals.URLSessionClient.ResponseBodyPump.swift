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
    /// not pulling from it, which is all waiting on the window does, makes CFNetwork stop reading
    /// off the socket once its own read-ahead is full. Against a server counting the bytes its
    /// kernel accepted, a reader that stops leaves the connection stalled around 4-5 MiB past what
    /// it read (pinned by `InternalsURLSessionClientBackPressureTests`). The delegate callback that
    /// would give more control is private CFNetwork API, so `AsyncBytes` is the supported way in.
    ///
    /// ## Chunking
    ///
    /// `AsyncBytes` hands out one byte at a time and says nothing about where CFNetwork's own
    /// deliveries end. Appending to `downloadBuffer` per byte would cost a queue operation each,
    /// and batching into fixed-size blocks would hold a slow stream's bytes back. So bytes are
    /// handed on exactly where `Internals.DownloadBuffer` could next emit a chunk (every
    /// `.length(n)` boundary, or the last byte of a `.separator`), and otherwise at most every
    /// `maximumPendingBytes`, which only bounds this function's own buffer. A `.separator` match
    /// can straddle two flushes; `DownloadBuffer`'s matcher carries its state across appends.
    ///
    /// `.passthrough` has no boundary, and waiting for `maximumPendingBytes` would starve what
    /// `DownloadBuffer.append` feeds: the read timeout (`Internals.IdleDeadline`) and the progress
    /// observer, which a body that is slow but steady (a long poll, a report built piece by piece)
    /// would only reach once per 64 KiB. So it is handed on where the stream is about to run dry:
    /// `AsyncBytes` suspends only once everything CFNetwork delivered has been pulled, and
    /// `URLSessionTask.countOfBytesReceived` says how much that is, so the loop pulls exactly what
    /// is there and flushes before the pull that would wait. A fast stream keeps being pulled
    /// without ever running dry and is flushed every `maximumPendingBytes`, as before. The count
    /// is read once per run, not per byte. Should it ever be behind what was pulled (a task that
    /// does not count), the flush falls back to every `unhintedFlushBytes`.
    ///
    /// ## Cost
    ///
    /// Every byte is an `async` call, hence one tight loop per reading mode below, writing into
    /// raw storage, rather than a general-purpose accumulator. Over loopback a bare
    /// `for try await _ in bytes` tops out around 1.5-3 GB/s optimized but only ~22 MiB/s in a
    /// Debug build; this loop alone manages ~400 MiB/s and ~35 MiB/s respectively.
    ///
    /// ## Liveness
    ///
    /// Only waits right after handing `downloadBuffer` everything it had pending, never while
    /// holding bytes back, so every byte the window counts is one the reader can drain on its own
    /// (the invariant `Internals.FlowControlWindow`'s "Liveness" section asks of every producer).
    /// Anything that ends the exchange without the reader draining the window releases it
    /// instead, after which this never waits again. A suspension shuts the same window, so a
    /// suspended exchange parks here at its next flush.
    ///
    /// ## Failure
    ///
    /// Whatever was already pulled when `bytes` throws is still handed to `downloadBuffer` before
    /// the error propagates: a continuation of the download (see `Internals.RangeResumptionPlan`)
    /// starts from the count in `deliveredBytes`, which has to match what the reader got.
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

            case .separator(let separator, _) where !separator.isEmpty:
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

            case .passthrough:
                // No boundary to flush on, so what decides is whether the stream is about to run
                // dry: a body that is slow but steady (a long poll, a report built piece by piece)
                // must reach `downloadBuffer`, and so feed the read timeout and the progress
                // observer, as it arrives, not once `capacity` bytes of it have piled up.
                //
                // `AsyncBytes` suspends only when what CFNetwork delivered so far is used up, and
                // `countOfBytesReceived` is how much it delivered (to the byte, also when
                // `URLSession` itself decodes the body). So the loop pulls exactly what is already
                // there, in runs, and hands over whatever it holds right before the pull that
                // would wait. A fast stream is pulled in runs as long as `capacity`, and flushes
                // only there.
                let task = bytes.task
                var pulled: Int64 = 0

                // Until the counter turns out to be behind what was pulled, which a task that
                // counts cannot be (none is known not to): then it is not telling where the stream
                // runs dry, and asking it again would flush one byte at a time. The flush falls
                // back to a fixed size small enough to keep a slow body moving.
                var isCounted = true

                streaming: while true {
                    var run = max(Self.unhintedFlushBytes - count, 1)

                    if isCounted {
                        let available = task.countOfBytesReceived &- pulled

                        if available < .zero {
                            isCounted = false
                            continue streaming
                        }

                        if available == .zero {
                            // The pull below suspends until more arrives: nothing held back may
                            // wait for that.
                            if count > .zero {
                                await flush()
                            }

                            run = 1
                        } else {
                            run = Int(clamping: min(available, Int64(capacity - count)))
                        }
                    }

                    let limit = count &+ run

                    while count < limit {
                        guard let byte = try await iterator.next() else {
                            break streaming
                        }

                        storage[count] = byte
                        count &+= 1
                    }

                    pulled &+= Int64(run)

                    if count >= (isCounted ? capacity : Self.unhintedFlushBytes) {
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
        // Adopted, not written: `replace(with:)` would copy the block into the store again.
        Internals.DataBuffer(Internals.ByteURL(adopting: data))
    }

    /// The most bytes `pumpResponseBody` holds back before a flush regardless of `readingMode`.
    /// Only bounds its own buffer; it has no bearing on what the reader sees, since
    /// `Internals.DownloadBuffer` re-chunks whatever it is given.
    static let maximumPendingBytes = 65_536

    /// How many bytes of a `.passthrough` body `pumpResponseBody` holds back when it cannot tell
    /// from the task's byte count where the stream is about to run dry. The size `.length` chunks
    /// had by default when the body went through `Internals.DownloadBuffer` one chunk at a time.
    static let unhintedFlushBytes = 1_024
}

#endif
