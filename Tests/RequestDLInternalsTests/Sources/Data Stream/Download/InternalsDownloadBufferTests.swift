//
// See LICENSE for this package's licensing information.
//

import Crypto
import SwiftAsyncTesting
import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsDownloadBufferTests {

    @Test
    func download_whenAppendingTotalLength_shouldContainsOneFragment() async throws {
        // Given
        let data = Data(repeating: .min, count: 1_024)
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024))

        // When
        await download.append(Internals.DataBuffer(data))
        download.close()

        // Then
        let bytes = try await Array(
            Internals.AsyncBytes(
                logger: nil,
                totalSize: data.count,
                stream: download.stream
            )
        )

        #expect(bytes == [data])
    }

    @Test
    func download_whenAppendingErrorBeforeData_shouldBeEmpty() async throws {
        // Given
        let data = Data(repeating: .min, count: 1_024)
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024))

        // When
        download.failed(AnyError())
        await download.append(Internals.DataBuffer(data))
        download.close()

        var receivedData = Data()
        var errors = [Error]()

        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: data.count,
            stream: download.stream
        )

        do {
            for try await data in bytes {
                receivedData.append(data)
            }
        } catch {
            errors.append(error)
        }

        // Then
        #expect(receivedData.isEmpty)
        #expect(errors.count == 1)
    }

    @Test
    func download_whenAppendingDifferentSizes_shouldMergeByLength() async throws {
        // Given
        let length = 1_024

        let part1 = Data(repeating: 64, count: length / 2)
        let part2 = Data(repeating: 32, count: length * 3)
        let part3 = Data(repeating: 128, count: length / 4)
        let part4 = Data(repeating: 16, count: length * 2)

        let download = await Internals.DownloadBuffer(readingMode: .length(length))

        // When
        await download.append(Internals.DataBuffer(part1))
        await download.append(Internals.DataBuffer(part2))
        await download.append(Internals.DataBuffer(part3))
        await download.append(Internals.DataBuffer(part4))
        download.close()

        // Then
        let parts = part1 + part2 + part3 + part4
        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: parts.count,
            stream: download.stream
        )

        let receivedBytes = try await Array(bytes)
        let expectedBytes = await Array(parts).split(by: length)

        #expect(receivedBytes == expectedBytes)
    }

    @Test
    func download_whenAppendingWithSplitByByte_shouldContainsFragmentsEndeingWithByte() async throws {
        // Given
        let separator = Data(",".utf8)

        let line1 = Data("0;00;000;0000;00000,".utf8)
        let line2 = Data("1;2;4;8;16,".utf8)
        let line3 = Data("32;64;128;256;512".utf8)

        let download = await Internals.DownloadBuffer(readingMode: .separator(Array(separator)))

        // When
        await download.append(Internals.DataBuffer(line1 + line2))
        await download.append(Internals.DataBuffer(line3))
        download.close()

        // Then
        let parts = line1 + line2 + line3
        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: parts.count,
            stream: download.stream
        )

        let receivedBytes = try await Array(bytes)
        let expectedBytes = await Array(parts).split(separator: Array(separator))

        #expect(receivedBytes == expectedBytes)
    }

    @Test
    func download_whenAppendingOnlySeparator_shouldContainsTwoFragments() async throws {
        // Given
        let separator = Data(",".utf8)

        let download = await Internals.DownloadBuffer(readingMode: .separator(Array(separator)))

        // When
        await download.append(Internals.DataBuffer(separator))
        download.close()

        // Then
        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: separator.count,
            stream: download.stream
        )

        let receivedBytes = try await Array(bytes)
        let expectedBytes = await Array(separator).split(separator: Array(separator))

        #expect(receivedBytes == expectedBytes)
    }

    // KMP-based separator scan: "aab" against "aaab" forces a failed
    // match at index 2 (`aa` + `a` != `aab`'s 3rd byte `b`) that must fall back to a partial
    // match of length 1 (not reset straight to 0), or the following "ab" would be missed and
    // the whole input would come back as one unsplit chunk instead of two.
    @Test
    func download_whenSeparatorHasARepeatingPrefix_backtracksInsteadOfMissingTheMatch() async throws {
        // Given
        let separator = Data("aab".utf8)
        let input = Data("aaab".utf8)

        let download = await Internals.DownloadBuffer(readingMode: .separator(Array(separator)))

        // When
        await download.append(Internals.DataBuffer(input))
        download.close()

        // Then
        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: input.count,
            stream: download.stream
        )

        let receivedBytes = try await Array(bytes)
        let expectedBytes = await Array(input).split(separator: Array(separator))

        #expect(receivedBytes == expectedBytes)
    }

    // A multi-byte separator split across two `append` calls right in the middle of a match:
    // the first call ends mid-separator, and the streaming match state has to carry over to
    // the second call for the split to still be found.
    @Test
    func download_whenMultiByteSeparatorStraddlesTwoAppends_stillSplits() async throws {
        // Given
        let separator = Data("--boundary".utf8)

        let line1 = Data("first--bound".utf8)
        let line2 = Data("ary,second".utf8)

        let download = await Internals.DownloadBuffer(readingMode: .separator(Array(separator)))

        // When
        await download.append(Internals.DataBuffer(line1))
        await download.append(Internals.DataBuffer(line2))
        download.close()

        // Then
        let parts = line1 + line2
        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: parts.count,
            stream: download.stream
        )

        let receivedBytes = try await Array(bytes)
        let expectedBytes = await Array(parts).split(separator: Array(separator))

        #expect(receivedBytes == expectedBytes)
    }

    @Test
    func download_whenEmpty_shouldBeEmpty() async throws {
        // Given
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024))

        // When
        download.close()

        // Then
        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: .zero,
            stream: download.stream
        )

        let receivedBytes = try await Array(bytes)
        let expectedBytes = [Data]()

        #expect(receivedBytes == expectedBytes)
    }

    @Test
    func download_whenMBAppending_shouldBeEqual() async throws {
        // Given
        let length = 4_096
        let data = Data(repeating: 64, count: 100_000_000)
        let download = await Internals.DownloadBuffer(readingMode: .length(length))

        // When
        await download.append(Internals.DataBuffer(data))
        download.close()

        // Then
        let bytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: data.count,
            stream: download.stream
        )

        let receivedBytes = try await Array(bytes)
        let expectedBytes = await Array(data).split(by: length)

        #expect(receivedBytes == expectedBytes)
    }

    // MARK: - maximumItemSize

    /// A stream that never sends the separator must not be accumulated without limit. The flow
    /// control window cannot slow it down, because bytes absorbed into the accumulator are
    /// credited back at once (they would otherwise hold the window shut against the very bytes
    /// that complete an item).
    @Test
    func download_whenNoSeparatorArrivesWithinTheMaximum_failsWithItemTooLarge() async throws {
        // Given
        let download = await Internals.DownloadBuffer(
            readingMode: .separator(Array("\n".utf8), maximumItemSize: 10)
        )

        // When: 4 + 4 + 4 bytes, none of them a separator.
        await download.append(Internals.DataBuffer(Data("aaaa".utf8)))
        await download.append(Internals.DataBuffer(Data("bbbb".utf8)))
        await download.append(Internals.DataBuffer(Data("cccc".utf8)))
        await download.waitUntilIdle()

        // Then
        let bytes = Internals.AsyncBytes(logger: nil, totalSize: 12, stream: download.stream)

        await #expect(throws: Internals.ReadingModeItemTooLargeError(maximumItemSize: 10)) {
            _ = try await Array(bytes)
        }
    }

    @Test
    func download_whenItemsFitTheMaximum_areDeliveredWholeAndTheSeparatorCountsTowardsIt() async throws {
        // Given: each item is exactly 10 bytes including its separator.
        let download = await Internals.DownloadBuffer(
            readingMode: .separator(Array("\n".utf8), maximumItemSize: 10)
        )

        // When
        await download.append(Internals.DataBuffer(Data("aaaaaaaaa\nbbbbb".utf8)))
        await download.append(Internals.DataBuffer(Data("bbbb\n".utf8)))
        download.close()

        // Then
        let bytes = Internals.AsyncBytes(logger: nil, totalSize: 20, stream: download.stream)
        let received = try await Array(bytes)

        #expect(received == [Data("aaaaaaaaa\n".utf8), Data("bbbbbbbbb\n".utf8)])
    }

    @Test
    func download_whenAnItemIsOneByteOverTheMaximum_fails() async throws {
        // Given: 11 bytes with the separator, against a maximum of 10.
        let download = await Internals.DownloadBuffer(
            readingMode: .separator(Array("\n".utf8), maximumItemSize: 10)
        )

        // When
        await download.append(Internals.DataBuffer(Data("aaaaaaaaaa\n".utf8)))
        await download.waitUntilIdle()

        // Then
        let bytes = Internals.AsyncBytes(logger: nil, totalSize: 11, stream: download.stream)

        await #expect(throws: Internals.ReadingModeItemTooLargeError(maximumItemSize: 10)) {
            _ = try await Array(bytes)
        }
    }

    @Test
    func download_whenItemsBeforeTheOversizedOneFit_stillDeliversThemFirst() async throws {
        // Given
        let download = await Internals.DownloadBuffer(
            readingMode: .separator(Array("\n".utf8), maximumItemSize: 5)
        )

        // When
        await download.append(Internals.DataBuffer(Data("ab\ncd\nefghijklmn".utf8)))
        await download.waitUntilIdle()

        // Then
        let bytes = Internals.AsyncBytes(logger: nil, totalSize: 17, stream: download.stream)
        var iterator = bytes.makeAsyncIterator()

        #expect(try await iterator.next().map { Array($0) } == Array("ab\n".utf8))
        #expect(try await iterator.next().map { Array($0) } == Array("cd\n".utf8))

        await #expect(throws: Internals.ReadingModeItemTooLargeError(maximumItemSize: 5)) {
            _ = try await iterator.next()
        }
    }

    @Test
    func download_whenNoMaximumIsGiven_keepsAccumulatingAsBefore() async throws {
        // Given
        let download = await Internals.DownloadBuffer(readingMode: .separator(Array("\n".utf8)))
        let line = Data(repeating: UInt8(ascii: "x"), count: 100_000)

        // When
        await download.append(Internals.DataBuffer(line))
        await download.append(Internals.DataBuffer(Data("\n".utf8)))
        download.close()

        // Then
        let bytes = Internals.AsyncBytes(logger: nil, totalSize: line.count + 1, stream: download.stream)

        #expect(try await Array(bytes).map(\.count) == [100_001])
    }

    // MARK: - A buffer that cannot be read

    /// `Internals.Buffer` answers `nil` for a read that failed, the same answer as the end of
    /// the data. A body whose backing storage cannot be read (here an encrypted entry whose tag
    /// does not match) must fail the stream instead of closing it normally, or it reaches the
    /// caller as a short body that succeeded.
    @Test(arguments: [
        Internals.DownloadStep.ReadingMode.length(1_024),
        .separator(Array("\n".utf8)),
        .passthrough,
    ])
    func download_whenTheIncomingBufferCannotBeRead_failsInsteadOfEndingTheBody(
        _ readingMode: Internals.DownloadStep.ReadingMode
    ) async throws {
        try await withTemporaryFileURL("encrypted.bin") { fileURL in
            // Given: an encrypted buffer written whole, then one byte of it changed.
            let url = Internals.EncryptedFileBufferURL(inner: .init(fileURL), key: .init(size: .bits256))

            var writer = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            await writer.writeData(Data("some content of the response\n".utf8))
            try await writer.close()

            var raw = try Data(contentsOf: fileURL)
            raw[raw.count - 1] ^= 0xFF
            try raw.write(to: fileURL)

            let reader = await Internals.Buffer<Internals.EncryptedFileStreamBuffer>(addressing: url)
            #expect(reader.readableBytes > 0)

            // When
            let download = await Internals.DownloadBuffer(readingMode: readingMode)
            download.append(reader)
            download.close()

            // Then
            let bytes = Internals.AsyncBytes(logger: nil, totalSize: reader.readableBytes, stream: download.stream)

            await #expect(throws: AsyncBytesReadError.self) {
                _ = try await Array(bytes)
            }
        }
    }

    // MARK: - Chunks cut out of large blocks

    /// The incoming buffer is read in blocks much larger than a chunk and cut up in memory. The
    /// chunks must come out the same as if it had been read chunk by chunk, wherever a block
    /// ends relative to a chunk.
    @Test(arguments: [1, 1_000, 1_024, 65_536, 70_000, 200_001])
    func download_whenAppendingMoreThanOneBlock_cutsExactChunksInOrder(_ length: Int) async throws {
        // Given: not a multiple of any of the chunk sizes, so the last chunk is short.
        let input = Data((0..<200_000).map { UInt8($0 % 251) })
        let download = await Internals.DownloadBuffer(readingMode: .length(length))

        // When
        await download.append(Internals.DataBuffer(input))
        download.close()

        // Then
        let bytes = Internals.AsyncBytes(logger: nil, totalSize: input.count, stream: download.stream)
        let chunks = try await Array(bytes)

        #expect(chunks.dropLast().allSatisfy { $0.count == length })
        #expect((chunks.last?.count ?? 0) <= length)
        #expect(chunks.reduce(into: Data()) { $0.append($1) } == input)
        #expect(chunks.count == (input.count + length - 1) / length)
    }

    @Test
    func download_whenAppendingInSeveralCalls_keepsFillingTheSameChunk() async throws {
        // Given: pieces that do not line up with the chunk size.
        let download = await Internals.DownloadBuffer(readingMode: .length(1_000))
        let first = Data(repeating: 1, count: 700)
        let second = Data(repeating: 2, count: 700)
        let third = Data(repeating: 3, count: 600)

        // When
        await download.append(Internals.DataBuffer(first))
        await download.append(Internals.DataBuffer(second))
        await download.append(Internals.DataBuffer(third))
        download.close()

        // Then
        let bytes = Internals.AsyncBytes(logger: nil, totalSize: 2_000, stream: download.stream)
        let chunks = try await Array(bytes)

        #expect(chunks.map(\.count) == [1_000, 1_000])
        #expect(chunks[0] == first + second.prefix(300))
        #expect(chunks[1] == second.suffix(400) + third)
    }

    // MARK: - Passthrough

    @Test
    func download_whenPassthrough_forwardsEachPartUntouched() async throws {
        // Given: parts that line up with no chunk size at all.
        let parts = [
            Data(repeating: 1, count: 1),
            Data(repeating: 2, count: 70_000),
            Data(repeating: 3, count: 1_025),
        ]

        let download = await Internals.DownloadBuffer(readingMode: .passthrough)

        // When
        for part in parts {
            await download.append(Internals.DataBuffer(part))
        }

        download.close()

        // Then
        let bytes = Internals.AsyncBytes(logger: nil, totalSize: 71_026, stream: download.stream)
        #expect(try await Array(bytes) == parts)
    }

    @Test
    func download_whenPassthrough_doesNotCopyAnInMemoryPart() async throws {
        // Given
        let part = await Internals.DataBuffer(Data(repeating: 7, count: 4_096))
        let download = await Internals.DownloadBuffer(readingMode: .passthrough)

        // When
        await download.append(part)
        download.close()

        // Then: the very store that was appended comes out of the stream, not a copy of it, which
        // a write straight to that store shows.
        var iterator = download.stream.makeAsyncIterator()
        var forwarded = try #require(await iterator.next())

        try await part.setData(Data([9]), at: 0)

        #expect(forwarded.readableBytes == 4_096)
        #expect(await forwarded.readData(1) == Data([9]))
    }

    @Test
    func download_whenPassthrough_skipsEmptyPartsAndKeepsOrder() async throws {
        // Given
        let download = await Internals.DownloadBuffer(readingMode: .passthrough)

        // When
        await download.append(Internals.DataBuffer(Data()))
        await download.append(Internals.DataBuffer(Data([1, 2, 3])))
        await download.append(Internals.DataBuffer(Data()))
        await download.append(Internals.DataBuffer(Data([4])))
        download.close()

        // Then
        let bytes = Internals.AsyncBytes(logger: nil, totalSize: 4, stream: download.stream)
        let chunks = try await Array(bytes)

        #expect(chunks.reduce(into: Data()) { $0.append($1) } == Data([1, 2, 3, 4]))
        #expect(chunks.allSatisfy { !$0.isEmpty })
    }

    @Test
    func download_whenPassthroughReadsABodyBehindTheFileSystem_deliversItInBoundedBlocks() async throws {
        try await withTemporaryFileURL("body.bin") { fileURL in
            // Given: a body of several blocks, behind a file, as a cached body is.
            let input = Data((0..<200_000).map { UInt8($0 % 251) })
            try input.write(to: fileURL)

            let source = await Internals.Buffer<Internals.FileStreamBuffer>(addressing: .init(fileURL))
            let download = await Internals.DownloadBuffer(readingMode: .passthrough)

            // When
            download.append(source)
            download.close()

            // Then: never the whole entry at once, and nothing lost.
            let bytes = Internals.AsyncBytes(logger: nil, totalSize: input.count, stream: download.stream)
            let chunks = try await Array(bytes)

            #expect(chunks.count > 1)
            #expect(chunks.allSatisfy { $0.count <= 65_536 })
            #expect(chunks.reduce(into: Data()) { $0.append($1) } == input)
        }
    }

    @Test
    func download_whenToldToPassThrough_stopsCuttingWhatFollows() async throws {
        // Given: a reading mode that would have cut these parts apart.
        let download = await Internals.DownloadBuffer(readingMode: .length(4))
        let parts = [Data("hello ".utf8), Data("world".utf8)]

        // When
        download.passThrough()

        for part in parts {
            await download.append(Internals.DataBuffer(part))
        }

        download.close()

        // Then
        let bytes = Internals.AsyncBytes(logger: nil, totalSize: 11, stream: download.stream)
        #expect(try await Array(bytes) == parts)
    }

    // MARK: - Cache tee

    /// Reads a cache stream to its end, keeping what arrived and how it ended.
    private func drain(
        _ cacheStream: Internals.AsyncStream<Internals.DataBuffer>
    ) async -> (received: Int, error: (any Error)?) {
        var received = 0

        do {
            for try await var chunk in cacheStream {
                received += chunk.readableBytes
                _ = await chunk.readData(chunk.readableBytes)
            }

            return (received, nil)
        } catch {
            return (received, error)
        }
    }

    @Test
    func cacheStream_whenTheWriterNeverReads_givesUpAtItsWindowInsteadOfBufferingTheBody() async throws {
        // Given: a tee whose window holds 4 KiB, and a writer that has not started reading.
        let window = Internals.FlowControlWindow(highWatermark: 4_096, lowWatermark: 2_048)
        let cacheStream = Internals.AsyncStream<Internals.DataBuffer>(flowControl: window)
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024))
        download.cacheStream(cacheStream)

        // When: 64 KiB goes through.
        let input = Data((0..<65_536).map { UInt8($0 % 251) })
        await download.append(Internals.DataBuffer(input))
        download.close()
        await download.waitUntilIdle()

        // Then: the download itself is whole.
        let bytes = Internals.AsyncBytes(logger: nil, totalSize: input.count, stream: download.stream)
        #expect(try await Array(bytes).reduce(into: Data()) { $0.append($1) } == input)

        // And the tee kept a window's worth, then failed, rather than keeping everything or
        // ending as though it were complete.
        let (received, error) = await drain(cacheStream)

        #expect(error is Internals.CacheBacklogExceededError)
        #expect(received >= 4_096)
        #expect(received <= 4_096 + 1_024)
    }

    @Test
    func cacheStream_whenTheWriterKeepsUp_receivesTheWholeBody() async throws {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 4_096, lowWatermark: 2_048)
        let cacheStream = Internals.AsyncStream<Internals.DataBuffer>(flowControl: window)
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024))
        download.cacheStream(cacheStream)

        let writer = Task { await drain(cacheStream) }

        // When: appended in parts, letting the writer run in between.
        for _ in 0..<64 {
            await download.append(Internals.DataBuffer(Data(repeating: 1, count: 1_024)))
            await download.waitUntilIdle()
            await Task.yield()
        }

        download.close()

        // Then
        let (received, error) = await writer.value

        #expect(error == nil)
        #expect(received == 65_536)
    }

    @Test
    func cacheStream_whenGivenUp_leavesTheDownloadFlowingAndTheLaterPartsUncounted() async throws {
        // Given
        let window = Internals.FlowControlWindow(highWatermark: 2_048, lowWatermark: 1_024)
        let cacheStream = Internals.AsyncStream<Internals.DataBuffer>(flowControl: window)
        let download = await Internals.DownloadBuffer(readingMode: .length(1_024))
        download.cacheStream(cacheStream)

        // When
        await download.append(Internals.DataBuffer(Data(repeating: 1, count: 100 * 1_024)))
        await download.waitUntilIdle()

        // Then: nothing past the first few chunks was charged to the tee's window.
        #expect(window.isWritable == false)
        #expect(window.bufferedBytesForTesting <= 2_048 + 1_024)

        download.close()
    }
}
