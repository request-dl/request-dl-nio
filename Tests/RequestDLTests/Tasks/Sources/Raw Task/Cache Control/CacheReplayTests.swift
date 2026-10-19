//
// See LICENSE for this package's licensing information.
//

@_spi(Testing) import RequestDLInternals
import Testing

import class Foundation.FileManager

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#elseif canImport(Android)
import Android
#endif

/// A cached body is fed to the download buffer in pieces with a flow-control window between
/// them, so it is not read into the response's stream whole however slowly it is being read, and
/// it is read in large blocks, not in chunks of the reading mode (1 KiB by default), one trip to
/// the file system each.
@Suite(
    .toleratingSimulatorFlake(
        "It waits for a replay to be scheduled, which a simulator runner starved of CPU for minutes (a test of this suite has waited 480s there) can't promise; the other platforms are what catch a regression"
    )
)
struct CacheReplayTests {

    /// Small, next to the default window of 1 MiB: these tests look at where a replay stops, which
    /// only needs the body to be longer than the window and one piece. 8 MiB through a debug
    /// build, several tests at a time, was most of the time a loaded runner spent on them.
    private let size = 1_024 * 1_024
    private let highWatermark = 128 * 1_024

    // The waits below are for the replay to be scheduled at all, not for it to be fast. A full
    // run on a busy Linux runner has stalled every task for longer than 30 s, which failed these
    // two on two runs in a row while the replay itself takes milliseconds.
    //
    // And they are for the replay to be parked at the window, which is a producer waiting on it,
    // not for the backlog to be above the high watermark: the download buffer re-chunks what the
    // replay hands it, and one run in twenty parks with exactly the high watermark buffered, so
    // "above" was never true and they waited their whole 120 s (three times in CI, on macOS,
    // Mac Catalyst and Linux).

    private func body() async -> Internals.AnyBuffer {
        // Not built element by element: 8 million closure calls in a debug build took the better
        // part of the wait under a loaded full run. These tests look at how much of it is read,
        // not at what it holds.
        await Internals.DataBuffer(Data(repeating: 0x5A, count: size))
    }

    @Test
    func replay_whileNobodyReads_stopsAtTheWindowInsteadOfBufferingTheWholeBody() async throws {
        // Given: a 1 MiB body, a 128 KiB window, and a reader that has not started.
        let window = Internals.FlowControlWindow(highWatermark: highWatermark, lowWatermark: highWatermark / 2)
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024), flowControl: window)

        // When
        let replay = _Concurrency.Task {
            await Internals.CacheControl.replay(await body(), into: download, window: window)
        }

        try await eventually(timeout: 120) { window.waitingCountForTesting == 1 }
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
        let window = Internals.FlowControlWindow(highWatermark: highWatermark, lowWatermark: highWatermark / 2)
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024), flowControl: window)

        let replay = _Concurrency.Task {
            await Internals.CacheControl.replay(await body(), into: download, window: window)
        }

        try await eventually(timeout: 120) { window.waitingCountForTesting == 1 }
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

    // MARK: - Reading the first piece before the response is handed out

    @Test
    func readPiece_ofAnEmptyBody_isEmptyNotUnreadable() async throws {
        var body: Internals.AnyBuffer = await Internals.DataBuffer(Data())

        let piece = await Internals.CacheControl.readPiece(of: &body)

        #expect(piece == [])
    }

    @Test
    func readPiece_ofABodyLargerThanAPiece_takesOnePieceAndLeavesTheRest() async throws {
        var body: Internals.AnyBuffer = await Internals.DataBuffer(
            Data(repeating: 0x5A, count: Internals.CacheControl.replayPieceSize + 7)
        )

        let piece = await Internals.CacheControl.readPiece(of: &body)

        #expect(piece?.count == Internals.CacheControl.replayPieceSize)
        #expect(body.readableBytes == 7)
    }

    /// The entry lookup found a file, and the file is gone by the time it is read.
    @Test
    func readPiece_whenTheFileIsGoneAfterTheLookup_isUnreadable() async throws {
        try await withTemporaryFileURL("entry.bin") { fileURL in
            try Data(repeating: 0x5A, count: 1_024).write(to: fileURL)
            var body: Internals.AnyBuffer = await Internals.FileBuffer(fileURL)

            try FileManager.default.removeItem(at: fileURL)

            let piece = await Internals.CacheControl.readPiece(of: &body)

            #expect(piece == nil)
        }
    }

    /// An I/O error that is not a missing file: the file is there, and the process may not read
    /// it. It is as unreadable as a removed one, a miss and not a failure.
    @Test(.disabled(if: geteuid() == 0, "root reads whatever it likes"))
    func readPiece_whenTheFileCannotBeRead_isUnreadable() async throws {
        try await withTemporaryFileURL("entry.bin") { fileURL in
            try Data(repeating: 0x5A, count: 1_024).write(to: fileURL)
            var body: Internals.AnyBuffer = await Internals.FileBuffer(fileURL)

            try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path) }

            let piece = await Internals.CacheControl.readPiece(of: &body)

            #expect(piece == nil)
        }
    }

    /// Another I/O error: a directory is where the file was.
    @Test
    func readPiece_whenADirectoryTookTheFilesPlace_isUnreadable() async throws {
        try await withTemporaryFileURL("entry.bin") { fileURL in
            try Data(repeating: 0x5A, count: 1_024).write(to: fileURL)
            var body: Internals.AnyBuffer = await Internals.FileBuffer(fileURL)

            try FileManager.default.removeItem(at: fileURL)
            try FileManager.default.createDirectory(at: fileURL, withIntermediateDirectories: false)

            let piece = await Internals.CacheControl.readPiece(of: &body)

            #expect(piece == nil)
        }
    }

    @Test
    func replay_startingWithAPiece_deliversItBeforeTheRest() async throws {
        // Given: a body whose first piece was already taken off.
        let input = Data((0..<200_000).map { UInt8($0 % 251) })
        var body: Internals.AnyBuffer = await Internals.DataBuffer(input)
        let first = try #require(await Internals.CacheControl.readPiece(of: &body))

        let window = Internals.FlowControlWindow()
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024), flowControl: window)

        // When
        await Internals.CacheControl.replay(body, startingWith: first, into: download, window: window)

        // Then: the whole body, once, in order.
        let bytes = Internals.AsyncBytes(logger: nil, totalSize: input.count, stream: download.stream)
        let received = try await Array(bytes).reduce(into: Data()) { $0.append($1) }

        #expect(received == input)
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
