//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncTesting
import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// `Internals.DownloadBuffer` metered by an `Internals.FlowControlWindow`, driven the way
/// `Internals.ClientResponseReceiver` drives it: append a part, then only append the next once the
/// window says so.
@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsDownloadBufferFlowControlTests {

    /// Deterministic, position-dependent bytes, so a reassembled body that dropped, repeated or
    /// reordered anything cannot compare equal by accident.
    private func pattern(_ range: Range<Int>) -> Data {
        Data(range.map { UInt8(truncatingIfNeeded: $0 % 251) })
    }

    private func readAll(_ stream: Internals.AsyncStream<Internals.DataBuffer>) async throws -> Data {
        var collected = Data()

        for try await chunk in Internals.AsyncBytes(logger: nil, totalSize: .zero, stream: stream) {
            collected += chunk
        }

        return collected
    }

    @Test
    func append_whileUnread_holdsTheWindowShutUntilTheReaderDrainsIt() async throws {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 4_096, lowWatermark: 2_048)
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024), flowControl: window)

        // When: 8 KiB arrive with nobody reading.
        for offset in stride(from: 0, to: 8_192, by: 1_024) {
            await download.append(Internals.DataBuffer(pattern(offset..<offset + 1_024)))
        }

        await download.waitUntilIdle()

        // Then: all of it is counted, so a producer honouring the window would be paused.
        #expect(window.bufferedBytesForTesting == 8_192)
        #expect(!window.isWritable)

        let resumed = LockedValueBox(false)
        window.whenWritable { resumed.withLockedValue { $0 = true } }

        // Reading takes chunks out one by one; the producer resumes only at the low watermark.
        var iterator = Internals.AsyncBytes(logger: nil, totalSize: .zero, stream: download.stream)
            .makeAsyncIterator()

        for _ in 0..<5 {
            _ = try await iterator.next()
        }

        #expect(window.bufferedBytesForTesting == 3_072)
        #expect(!resumed.withLockedValue { $0 })

        _ = try await iterator.next()

        #expect(window.bufferedBytesForTesting == 2_048)
        #expect(resumed.withLockedValue { $0 })
    }

    /// Bytes waiting in `DownloadBuffer`'s re-chunking accumulator for the rest of their chunk
    /// must not count against the window. A `.length(n)` chunk larger than the whole window can
    /// only ever be completed by more input, so counting it would hold the producer paused
    /// against exactly the input needed to release it: a deadlock the moment `n` exceeds the
    /// high watermark.
    @Test(arguments: [
        Internals.DownloadStep.ReadingMode.length(10_000),
        Internals.DownloadStep.ReadingMode.separator(Array("\r\n".utf8)),
    ])
    func append_whenAChunkOutgrowsTheWindow_neverHoldsTheProducerPaused(
        readingMode: Internals.DownloadStep.ReadingMode
    ) async throws {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 1_024, lowWatermark: 512)
        let download = await Internals.DownloadBuffer(readingMode: readingMode, flowControl: window)

        // A body with no chunk boundary anywhere in its first 9 KB, well past the window.
        let body = Data(repeating: 0x41, count: 9_000)

        // When: produced the way the NIO receiver produces, waiting for the window between parts,
        // with no reader at all.
        try await completing(within: 10) {
            for offset in stride(from: 0, to: body.count, by: 1_000) {
                await download.append(Internals.DataBuffer(body[offset..<offset + 1_000]))
                await window.waitUntilWritable()
            }
        }

        download.close()

        // Then: nothing was lost or duplicated along the way.
        let collected = try await readAll(download.stream)
        #expect(collected == body)
        #expect(window.bufferedBytesForTesting == 0)
    }

    /// A reader that stops for good releases the window, rather than leaving the producer (on the
    /// NIO path, a whole pooled connection) paused for something that can never come back.
    @Test
    func readerIteratorReleased_releasesTheWindow() async throws {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 1_024, lowWatermark: 512)
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024), flowControl: window)

        for offset in stride(from: 0, to: 8_192, by: 1_024) {
            await download.append(Internals.DataBuffer(pattern(offset..<offset + 1_024)))
        }

        await download.waitUntilIdle()

        let resumed = LockedValueBox(false)
        window.whenWritable { resumed.withLockedValue { $0 = true } }

        // When: one chunk read, then the reader goes away.
        do {
            var iterator = Internals.AsyncBytes(logger: nil, totalSize: .zero, stream: download.stream)
                .makeAsyncIterator()
            _ = try await iterator.next()

            #expect(!resumed.withLockedValue { $0 })
        }

        // Then
        #expect(resumed.withLockedValue { $0 })
        #expect(window.isReleasedForTesting)
    }

    /// A second reader, which only ever gets `AlreadyConsumedError`, must not release a window
    /// the first reader is still draining when it goes away.
    @Test
    func secondIteratorReleased_leavesTheWindowToTheFirstReader() async throws {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 1_024, lowWatermark: 512)
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024), flowControl: window)

        await download.append(Internals.DataBuffer(pattern(0..<4_096)))
        await download.waitUntilIdle()

        var first = download.stream.makeAsyncIterator()
        _ = try await first.next()

        // When
        do {
            var second = download.stream.makeAsyncIterator()
            await #expect(throws: AlreadyConsumedError.self) {
                _ = try await second.next()
            }
        }

        // Then
        #expect(!window.isReleasedForTesting)
        #expect(window.bufferedBytesForTesting == 3_072)

        withExtendedLifetime(first) {}
    }
}
