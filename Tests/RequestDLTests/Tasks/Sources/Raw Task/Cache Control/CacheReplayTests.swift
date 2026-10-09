//
// See LICENSE for this package's licensing information.
//

@_spi(Testing) import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// A cached body is fed to the download buffer in pieces with a flow-control window between
/// them, so it is not read into the response's stream whole however slowly it is being read, and
/// it is read in large blocks, not in chunks of the reading mode (1 KiB by default), one trip to
/// the file system each.
struct CacheReplayTests {

    private let size = 8 * 1_024 * 1_024

    // The waits below are for the replay to be scheduled at all, not for it to be fast. A full
    // run on a busy Linux runner has stalled every task for longer than 30 s, which failed these
    // two on two runs in a row while the replay itself takes milliseconds.

    private func body() async -> Internals.AnyBuffer {
        // Not built element by element: 8 million closure calls in a debug build took the better
        // part of the wait under a loaded full run. These tests look at how much of it is read,
        // not at what it holds.
        await Internals.DataBuffer(Data(repeating: 0x5A, count: size))
    }

    @Test
    func replay_whileNobodyReads_stopsAtTheWindowInsteadOfBufferingTheWholeBody() async throws {
        // Given: an 8 MiB body, a 1 MiB window, and a reader that has not started.
        let window = Internals.FlowControlWindow()
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024), flowControl: window)

        // When
        let replay = _Concurrency.Task {
            await Internals.CacheControl.replay(await body(), into: download, window: window)
        }

        try await eventually(timeout: 120) { window.bufferedBytesForTesting > window.highWatermark }
        await download.waitUntilIdle()

        // Then: it has paused, short of the whole body, by about one piece past the mark.
        let buffered = window.bufferedBytesForTesting
        #expect(buffered <= window.highWatermark + Internals.CacheControl.replayPieceSize)
        #expect(buffered < size)

        // When: the reader starts.
        let bytes = Internals.AsyncBytes(logger: nil, totalSize: size, stream: download.stream)
        var received = 0

        for try await chunk in bytes {
            received += chunk.count
        }

        await replay.value

        // Then: the whole body arrives.
        #expect(received == size)
    }

    @Test
    func replay_whenTheWindowIsReleased_stopsInsteadOfReadingTheRest() async throws {
        // Given: a replay parked at the window with nobody reading.
        let window = Internals.FlowControlWindow()
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024), flowControl: window)

        let replay = _Concurrency.Task {
            await Internals.CacheControl.replay(await body(), into: download, window: window)
        }

        try await eventually(timeout: 120) { window.bufferedBytesForTesting > window.highWatermark }
        await download.waitUntilIdle()
        let bufferedWhenParked = window.bufferedBytesForTesting

        // When: the reader goes away.
        window.release()
        await replay.value
        await download.waitUntilIdle()

        // Then: it did not go on to read the rest of the body into the stream.
        #expect(window.bufferedBytesForTesting <= bufferedWhenParked + Internals.CacheControl.replayPieceSize)
        #expect(window.bufferedBytesForTesting < size)
    }

    /// A body that is not a multiple of the piece size, and one smaller than a single piece, end
    /// with a piece of whatever is left.
    @Test(arguments: [0, 1, 100, 65_535, 65_536, 65_537, 200_000])
    func replay_deliversTheWholeBodyWhateverItsSize(_ count: Int) async throws {
        // Given
        let input = Data((0..<count).map { UInt8($0 % 251) })
        let window = Internals.FlowControlWindow()
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024), flowControl: window)

        // When
        await Internals.CacheControl.replay(await Internals.DataBuffer(input), into: download, window: window)

        // Then
        let bytes = Internals.AsyncBytes(logger: nil, totalSize: count, stream: download.stream)
        let received = try await Array(bytes).reduce(into: Data()) { $0.append($1) }

        #expect(received == input)
    }
}
