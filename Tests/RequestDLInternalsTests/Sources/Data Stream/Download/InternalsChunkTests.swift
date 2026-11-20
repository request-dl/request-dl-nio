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

#if canImport(NIOCore)
import NIOCore
#endif

/// `Internals.Chunk`, and `Internals.DownloadBuffer` delivering it: that the bytes come out the
/// way they went in whatever the reading mode, that the two streams of a tee never diverge, and
/// that a chunk neither keeps alive what it was cut from nor outlives its readers.
@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsChunkTests {

    // MARK: - Helpers

    /// A generator with a seed, so a failing case can be run again.
    private struct SplitMix64: RandomNumberGenerator {

        private var state: UInt64

        init(seed: UInt64) {
            self.state = seed
        }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Owns nothing but its own lifetime. A `Data` built around it keeps it alive for exactly as
    /// long as that `Data`'s storage is, which is what a `weak` reference to it can then show.
    private final class Owner: @unchecked Sendable {}

    /// A `Data` of `count` bytes (`pattern`) whose storage is held by `owner`.
    private func data(_ count: Int, ownedBy owner: Owner) -> Data {
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: max(count, 1), alignment: 1)

        for index in 0..<count {
            pointer.storeBytes(of: UInt8(truncatingIfNeeded: index % 251), toByteOffset: index, as: UInt8.self)
        }

        return Data(
            bytesNoCopy: pointer,
            count: count,
            deallocator: .custom { pointer, _ in
                _ = owner
                pointer.deallocate()
            }
        )
    }

    private func random(_ count: Int, using generator: inout SplitMix64) -> Data {
        Data((0..<count).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
    }

    /// Cuts `input` into packets of random sizes (some of one byte), the way a network does.
    private func packets(of input: Data, using generator: inout SplitMix64) -> [Data] {
        var packets: [Data] = []
        var offset = input.startIndex

        while offset < input.endIndex {
            let size = min(Int.random(in: 1...97, using: &generator), input.endIndex - offset)
            packets.append(input.subdata(in: offset..<offset + size))
            offset += size
        }

        return packets
    }

    private func chunks(of download: Internals.DownloadBuffer) async throws -> [Internals.Chunk] {
        var chunks: [Internals.Chunk] = []

        for try await chunk in download.stream {
            chunks.append(chunk)
        }

        return chunks
    }

    /// What reading `input` in `.separator` mode has to give, written the plain way: a cut after
    /// every occurrence, scanning from where the last one ended.
    private func split(_ input: [UInt8], on separator: [UInt8]) -> [[UInt8]] {
        var items: [[UInt8]] = []
        var start = 0
        var index = 0

        while index + separator.count <= input.count {
            if Array(input[index..<index + separator.count]) == separator {
                items.append(Array(input[start..<index + separator.count]))
                index += separator.count
                start = index
            } else {
                index += 1
            }
        }

        if start < input.count {
            items.append(Array(input[start...]))
        }

        return items
    }

    // MARK: - Reading modes

    @Test(arguments: [UInt64](1...40))
    func readingModes_whateverTheInputAndItsPackets_giveBackExactlyTheInput(seed: UInt64) async throws {
        var generator = SplitMix64(seed: seed)

        let input = random(Int.random(in: 0...6_000, using: &generator), using: &generator)
        let parts = packets(of: input, using: &generator)

        // `.passthrough`: one chunk per packet, in order.
        let passthrough = await Internals.DownloadBuffer(readingMode: .passthrough)
        for part in parts { passthrough.append(Internals.Chunk(part)) }
        passthrough.close()

        let passed = try await chunks(of: passthrough)
        #expect(passed.map(\.data) == parts)

        // `.length`: chunks of exactly `length`, the last one holding what is left.
        let length = Int.random(in: 1...300, using: &generator)
        let download = await Internals.DownloadBuffer(readingMode: .length(length))
        for part in parts { download.append(Internals.Chunk(part)) }
        download.close()

        let cut = try await chunks(of: download)
        #expect(cut.reduce(into: Data()) { $0 += $1.data } == input)
        #expect(cut.dropLast().allSatisfy { $0.readableBytes == length })
        #expect(cut.allSatisfy { $0.readableBytes <= length && !$0.isEmpty })
        #expect(cut.allSatisfy { $0.data.startIndex == .zero })

        // `.separator`, over bytes that make the separator frequent, so that it also lands
        // across the edge between two packets.
        let separator: [UInt8] = [0x0D, 0x0A, 0x0D]
        let alphabet: [UInt8] = [0x0D, 0x0A, 0x41]
        let textLength = Int.random(in: 0...2_000, using: &generator)
        let text = Data((0..<textLength).map { _ in alphabet.randomElement(using: &generator)! })
        let textParts = packets(of: text, using: &generator)

        let separated = await Internals.DownloadBuffer(readingMode: .separator(separator))
        for part in textParts { separated.append(Internals.Chunk(part)) }
        separated.close()

        let items = try await chunks(of: separated)
        #expect(items.map { Array($0.data) } == split(Array(text), on: separator))
        #expect(items.reduce(into: Data()) { $0 += $1.data } == text)
        #expect(items.allSatisfy { $0.data.startIndex == .zero })
    }

    @Test(arguments: [UInt64](1...20))
    func readingModes_whenTheInputComesFromABuffer_giveBackExactlyTheInput(seed: UInt64) async throws {
        var generator = SplitMix64(seed: seed)

        // The path of a cached body: not a chunk, read in blocks.
        let input = random(Int.random(in: 1...200_000, using: &generator), using: &generator)
        let length = Int.random(in: 1...5_000, using: &generator)

        let download = await Internals.DownloadBuffer(readingMode: .length(length))
        download.append(await Internals.DataBuffer(input))
        download.close()

        let cut = try await chunks(of: download)

        #expect(cut.reduce(into: Data()) { $0 += $1.data } == input)
        #expect(cut.dropLast().allSatisfy { $0.readableBytes == length })
    }

    @Test
    func separator_whenEmpty_hasNothingToCutOnAndKeepsEverythingForTheEnd() async throws {
        // Matching an empty separator would cut once per byte, so everything is remainder, and
        // comes out as one chunk when the body ends.
        let download = await Internals.DownloadBuffer(readingMode: .separator([]))
        download.append(Internals.Chunk(Data("one".utf8)))
        download.append(Internals.Chunk(Data("two".utf8)))
        download.close()

        let items = try await chunks(of: download)

        #expect(items.map(\.data) == [Data("onetwo".utf8)])
    }

    @Test
    func separator_splitAcrossPackets_isFoundWhereverTheCutFalls() async throws {
        let separator = Array("<->".utf8)
        let input = Array("one<->two<->three<->tail".utf8)

        // Every way of cutting the input in two: the separator ends up on either side of the cut,
        // and across it.
        for cut in 1..<input.count {
            let download = await Internals.DownloadBuffer(readingMode: .separator(separator))
            download.append(Internals.Chunk(Data(input[..<cut])))
            download.append(Internals.Chunk(Data(input[cut...])))
            download.close()

            let items = try await chunks(of: download).map { String(decoding: $0.data, as: UTF8.self) }

            #expect(items == ["one<->", "two<->", "three<->", "tail"], "cut at \(cut)")
        }
    }

    // MARK: - The tee

    @Test
    func tee_whileTheProducerAdvances_readerAndCacheNeverDiverge() async throws {
        var generator = SplitMix64(seed: 99)
        let input = random(100_000, using: &generator)

        let cacheStream = Internals.DownloadBuffer.makeCacheStream()
        let download = await Internals.DownloadBuffer(readingMode: .length(1_000))
        download.cacheStream(cacheStream)

        var readerIterator = download.stream.makeAsyncIterator()
        var cacheIterator = cacheStream.makeAsyncIterator()

        var held: [(reader: Internals.Chunk, cache: Internals.Chunk)] = []
        var offset = 0

        // Both sides hold what they took while the producer keeps appending, and while later
        // chunks are cut out of the very block the held ones came from.
        while offset < input.count {
            let end = min(offset + 4_096, input.count)
            download.append(Internals.Chunk(input.subdata(in: offset..<end)))
            offset = end

            await download.waitUntilIdle()

            if held.count < 20 {
                let reader = try #require(try await readerIterator.next())
                let cache = try #require(try await cacheIterator.next())

                held.append((reader, cache))
            }
        }

        download.close()

        var readerChunks = held.map(\.reader)
        var cacheChunks = held.map(\.cache)

        while let chunk = try await readerIterator.next() { readerChunks.append(chunk) }
        while let chunk = try await cacheIterator.next() { cacheChunks.append(chunk) }

        #expect(readerChunks == cacheChunks)
        #expect(readerChunks.reduce(into: Data()) { $0 += $1.data } == input)
        #expect(cacheChunks.reduce(into: Data()) { $0 += $1.data } == input)

        // What the two hold is the same bytes, not two copies of them.
        let shared = zip(readerChunks, cacheChunks).filter { reader, cache in
            reader.data.withUnsafeBytes { $0.baseAddress } == cache.data.withUnsafeBytes { $0.baseAddress }
        }

        #expect(shared.count == readerChunks.count)
    }

    @Test
    func tee_aCopyThatIsMutated_leavesTheOtherHolderAlone() async throws {
        let cacheStream = Internals.DownloadBuffer.makeCacheStream()
        let download = await Internals.DownloadBuffer(readingMode: .passthrough)
        download.cacheStream(cacheStream)

        download.append(Internals.Chunk(Data(repeating: 1, count: 2_048)))
        download.close()

        var readerIterator = download.stream.makeAsyncIterator()
        var cacheIterator = cacheStream.makeAsyncIterator()

        var readerData = try #require(try await readerIterator.next()).data
        let cacheChunk = try #require(try await cacheIterator.next())

        // The reader of a download is handed a `Data` it may well write to.
        readerData[0] = 9
        readerData[2_047] = 9

        #expect(cacheChunk.data == Data(repeating: 1, count: 2_048))
    }

    // MARK: - Release

    @Test
    func cancel_whileReading_releasesTheBytesOfWhatIsStillQueued() async throws {
        weak var weakOwner: Owner?

        do {
            let owner = Owner()
            weakOwner = owner

            let cacheStream = Internals.DownloadBuffer.makeCacheStream()
            let download = await Internals.DownloadBuffer(readingMode: .passthrough)
            download.cacheStream(cacheStream)

            let stream = download.stream

            // Several chunks over the same storage, none of them read yet.
            let block = data(8_192, ownedBy: owner)
            for _ in 0..<4 { download.append(Internals.Chunk(block)) }
            await download.waitUntilIdle()

            let reader = Task {
                var count = 0

                for try await _ in stream {
                    count += 1

                    // Parked mid-read: cancelled while holding a chunk, with more still queued.
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                }

                return count
            }

            // Lets the reader take its first chunk, then cancels it.
            await Task.yield()
            try await Task.sleep(nanoseconds: 50_000_000)
            reader.cancel()
            _ = try? await reader.value
        }

        // Nothing is left holding the storage: no lock, no cursor and no handle to be closed
        // first, only values that have all been let go of.
        await expectReleased { weakOwner == nil }
    }

    @Test
    func drop_withoutReading_releasesTheBytes() async throws {
        weak var weakOwner: Owner?

        do {
            let owner = Owner()
            weakOwner = owner

            let download = await Internals.DownloadBuffer(readingMode: .length(1_024))
            download.append(Internals.Chunk(data(65_536, ownedBy: owner)))
            await download.waitUntilIdle()
        }

        await expectReleased { weakOwner == nil }
    }

    // MARK: - Retention

    @Test
    func slicing_aSmallPieceOfABlock_doesNotKeepTheBlockAlive() async throws {
        weak var weakOwner: Owner?
        var small: Internals.Chunk?

        do {
            let owner = Owner()
            weakOwner = owner

            let block = data(65_536, ownedBy: owner)

            // The first kilobyte, which is where a shared slice would be allowed to start.
            small = Internals.Chunk(slicing: 0..<1_024, of: block)
        }

        #expect(weakOwner == nil)
        #expect(small?.data == Data((0..<1_024).map { UInt8(truncatingIfNeeded: $0 % 251) }))
        #expect(small?.data.startIndex == .zero)
    }

    @Test
    func slicing_aPieceFromTheMiddle_isCopiedWhateverItsSize() async throws {
        weak var weakOwner: Owner?
        var middle: Internals.Chunk?

        do {
            let owner = Owner()
            weakOwner = owner

            let block = data(65_536, ownedBy: owner)

            // Large, but it does not start at zero, so it could not be handed out as it is.
            middle = Internals.Chunk(slicing: 20_000..<60_000, of: block)
        }

        #expect(weakOwner == nil)
        #expect(middle?.readableBytes == 40_000)
        #expect(middle?.data.startIndex == .zero)
        #expect(middle?.data.first == UInt8(truncatingIfNeeded: 20_000 % 251))
    }

    @Test
    func slicing_mostOfABlockFromItsStart_sharesTheBlock() async throws {
        weak var weakOwner: Owner?
        var large: Internals.Chunk?

        do {
            let owner = Owner()
            weakOwner = owner

            let block = data(65_536, ownedBy: owner)

            // Past the threshold: sharing holds at most twice what the chunk is.
            large = Internals.Chunk(slicing: 0..<40_000, of: block)
        }

        #expect(weakOwner != nil)
        #expect(large?.readableBytes == 40_000)
        #expect(large?.data.startIndex == .zero)

        large = nil
        await expectReleased { weakOwner == nil }
    }

    @Test
    func length_aSmallChunkOfALargeBlock_doesNotPinTheBlockInTheStream() async throws {
        weak var weakOwner: Owner?
        var first: Internals.Chunk?

        do {
            let owner = Owner()
            weakOwner = owner

            let download = await Internals.DownloadBuffer(readingMode: .length(1_024))
            download.append(Internals.Chunk(data(65_536, ownedBy: owner)))
            download.close()

            // Only one chunk of the 64 that the block was cut into is kept, as a reader that
            // keeps hold of an item would.
            first = try await chunks(of: download).first
        }

        await expectReleased { weakOwner == nil }
        #expect(first?.readableBytes == 1_024)
    }

    // MARK: - The invariant

    @Test
    func init_ofADataThatDoesNotStartAtZero_isRebased() {
        let source = Data((0..<100).map { UInt8($0) })
        let chunk = Internals.Chunk(source[40..<60])

        #expect(chunk.data.startIndex == .zero)
        #expect(chunk.data == Data((40..<60).map { UInt8($0) }))
        #expect(chunk.data[0] == 40)
    }

    #if canImport(NIOCore)
    @Test(arguments: [0, 1, 4_096, 300_000])
    func init_ofAByteBuffer_startsAtZeroAndHoldsTheSameBytes(count: Int) {
        var buffer = ByteBuffer()
        buffer.writeBytes((0..<count).map { UInt8(truncatingIfNeeded: $0 % 251) })

        // A reader index that is not zero: what the chunk holds is the readable part only.
        let skipped = min(3, count)
        buffer.moveReaderIndex(forwardBy: skipped)

        let chunk = Internals.Chunk(buffer)

        #expect(chunk.data.startIndex == .zero)
        #expect(chunk.readableBytes == count - skipped)
        #expect(Array(chunk.data) == Array(buffer.readableBytesView))
    }
    #endif

    // MARK: - Waiting for a release

    /// Gives what is being torn down on other tasks a moment to finish, since a stream lets go
    /// of what it holds from the task that ends it.
    private func expectReleased(
        _ condition: () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<200 where !condition() {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        #expect(condition(), sourceLocation: sourceLocation)
    }
}
