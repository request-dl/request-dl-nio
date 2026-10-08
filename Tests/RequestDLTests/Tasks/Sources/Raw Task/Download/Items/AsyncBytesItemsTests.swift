//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import SwiftAsyncStream
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct AsyncBytesItemsTests {

    // MARK: - Helpers

    private func makeBytes(_ chunks: [String], onCancel: @escaping @Sendable () -> Void = {}) async -> AsyncBytes {
        await makeBytes(chunks.map { Data($0.utf8) }, onCancel: onCancel)
    }

    private func makeBytes(_ chunks: [Data], onCancel: @escaping @Sendable () -> Void = {}) async -> AsyncBytes {
        let stream = Internals.AsyncStream<Internals.DataBuffer>()

        let internalBytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: chunks.reduce(0) { $0 + $1.count },
            stream: stream
        )

        for chunk in chunks {
            await stream.append(.success(Internals.DataBuffer(chunk)))
        }

        stream.close()

        return AsyncBytes(seed: Internals.TaskSeed(onCancel), bytes: internalBytes)
    }

    private func collect<S: AsyncSequence>(_ sequence: S) async throws -> [S.Element] {
        var elements: [S.Element] = []

        for try await element in sequence {
            elements.append(element)
        }

        return elements
    }

    // MARK: - lines

    @Test
    func lines_splitsOnLFCRLFAndLoneCR() async throws {
        let bytes = await makeBytes(["one\ntwo\r\nthree\rfour\n"])

        #expect(try await collect(bytes.lines()) == ["one", "two", "three", "four"])
    }

    @Test
    func lines_whenCRLFIsSplitAcrossChunks_isOneBreak() async throws {
        let bytes = await makeBytes(["one\r", "\ntwo\r", "three"])

        #expect(try await collect(bytes.lines()) == ["one", "two", "three"])
    }

    @Test
    func lines_whenALineIsSplitAcrossChunks_isDeliveredWhole() async throws {
        let bytes = await makeBytes(["hel", "lo wo", "rld\nnext"])

        #expect(try await collect(bytes.lines()) == ["hello world", "next"])
    }

    @Test
    func lines_keepsEmptyLines_andDoesNotAddOneAfterTheLastBreak() async throws {
        let bytes = await makeBytes(["a\n\nb\n\n"])

        #expect(try await collect(bytes.lines()) == ["a", "", "b", ""])
    }

    @Test
    func lines_whenTheStreamIsEmpty_yieldsNothing() async throws {
        let bytes = await makeBytes([String]())

        #expect(try await collect(bytes.lines()).isEmpty)
    }

    @Test
    func lines_whenALineIsExactlyAtTheMaximum_isDelivered() async throws {
        let bytes = await makeBytes(["12345\n67890"])

        #expect(try await collect(bytes.lines(maximumLength: 5)) == ["12345", "67890"])
    }

    @Test
    func lines_whenALineIsOneByteOverTheMaximum_failsAfterTheEarlierLines() async throws {
        let bytes = await makeBytes(["ok\n123456\nnever\n"])
        var iterator = bytes.lines(maximumLength: 5).makeAsyncIterator()

        #expect(try await iterator.next() == "ok")

        await #expect(throws: AsyncBytesItemTooLargeError(maximumLength: 5)) {
            _ = try await iterator.next()
        }

        // The sequence is over: nothing after the failure is read.
        #expect(try await iterator.next() == nil)
    }

    @Test
    func lines_whenALineNeverEnds_failsOnceItPassesTheMaximum() async throws {
        let chunk = String(repeating: "x", count: 1_024)
        let bytes = await makeBytes([String](repeating: chunk, count: 200))

        await #expect(throws: AsyncBytesItemTooLargeError(maximumLength: 10_000)) {
            _ = try await collect(bytes.lines(maximumLength: 10_000))
        }
    }

    @Test
    func lines_whenTheLastLineHasNoBreakAndIsOverTheMaximum_fails() async throws {
        let bytes = await makeBytes(["ok\n", "123456"])

        await #expect(throws: AsyncBytesItemTooLargeError(maximumLength: 5)) {
            _ = try await collect(bytes.lines(maximumLength: 5))
        }
    }

    // MARK: - items

    @Test
    func items_whenTheSeparatorIsSplitAcrossChunks_isFound() async throws {
        let bytes = await makeBytes(["head\r", "\n\r", "\nbody", "\r\n", "\r\ntail"])

        let items = try await collect(bytes.items(separatedBy: "\r\n\r\n"))

        #expect(items == [Data("head".utf8), Data("body".utf8), Data("tail".utf8)])
    }

    @Test
    func items_whenTwoSeparatorsFollowEachOther_yieldsAnEmptyItem() async throws {
        let bytes = await makeBytes([Data([0x1, 0x1E, 0x1E, 0x2, 0x1E])])

        let items = try await collect(bytes.items(separatedBy: [0x1E]))

        #expect(items == [Data([0x1]), Data(), Data([0x2])])
    }

    @Test
    func items_whenAnItemIsExactlyAtTheMaximumWithALongSeparator_isDelivered() async throws {
        let bytes = await makeBytes(["abcde<>", "fgh", "ij<", ">"])

        let items = try await collect(bytes.items(separatedBy: "<>", maximumLength: 5))

        #expect(items == [Data("abcde".utf8), Data("fghij".utf8)])
    }

    @Test
    func items_whenAnItemIsOneByteOverTheMaximumWithALongSeparator_fails() async throws {
        let bytes = await makeBytes(["abcdef", "<", ">"])

        await #expect(throws: AsyncBytesItemTooLargeError(maximumLength: 5)) {
            _ = try await collect(bytes.items(separatedBy: "<>", maximumLength: 5))
        }
    }

    @Test
    func items_whenTheItemEndsInAHalfSeparator_doesNotCountItAsContent() async throws {
        // Five bytes of content and the first byte of the separator, still at the maximum.
        let bytes = await makeBytes(["abcde<", ">"])

        #expect(
            try await collect(bytes.items(separatedBy: "<>", maximumLength: 5)) == [Data("abcde".utf8)]
        )
    }

    // MARK: - Cancelling the transfer

    @Test
    func lines_whenALineOutgrowsTheMaximum_cancelsTheTransferWhileTheCallerStillHoldsTheBytes() async throws {
        let cancelled = CancelFlag()
        let bytes = await makeBytes(["123456\n"], onCancel: { cancelled.set() })

        await #expect(throws: AsyncBytesItemTooLargeError(maximumLength: 5)) {
            _ = try await collect(bytes.lines(maximumLength: 5))
        }

        // `bytes` is still alive here, so dropping it is not what ended the transfer.
        #expect(cancelled.isSet)
        withExtendedLifetime(bytes) {}
    }

    @Test
    func lines_whenEveryLineIsWithinTheMaximum_doesNotCancelTheTransfer() async throws {
        let cancelled = CancelFlag()
        let bytes = await makeBytes(["a\nb\n"], onCancel: { cancelled.set() })

        _ = try await collect(bytes.lines())

        #expect(!cancelled.isSet)
        withExtendedLifetime(bytes) {}
    }

    @Test
    func lines_whenTheReaderStopsEarlyAndLetsGo_cancelsTheTransfer() async throws {
        let cancelled = CancelFlag()

        do {
            let bytes = await makeBytes(["a\nb\nc\n"], onCancel: { cancelled.set() })

            for try await line in bytes.lines() {
                #expect(line == "a")
                break
            }

            #expect(!cancelled.isSet)
        }

        try await eventually { cancelled.isSet }
    }

    @Test
    func readingModeItemTooLarge_cancelsTheTransferWhileTheCallerStillHoldsTheBytes() async throws {
        let cancelled = CancelFlag()
        let stream = Internals.AsyncStream<Internals.DataBuffer>()
        let internalBytes = Internals.AsyncBytes(logger: nil, totalSize: 0, stream: stream)
        let bytes = AsyncBytes(seed: Internals.TaskSeed { cancelled.set() }, bytes: internalBytes)

        await stream.append(.failure(Internals.ReadingModeItemTooLargeError(maximumItemSize: 5)))
        stream.close()

        await #expect(throws: ReadingModeItemTooLargeError.self) {
            for try await _ in bytes {}
        }

        #expect(cancelled.isSet)
        withExtendedLifetime(bytes) {}
    }

    // MARK: - ItemSplitter

    @Test
    func splitter_keepsAtMostTheMaximumPlusOneChunkWhenAnItemNeverEnds() {
        var splitter = ItemSplitter(delimiter: .lineBreak, maximumLength: 4_096)
        let chunk = Data(repeating: UInt8(ascii: "x"), count: 1_024)
        var fed = 0

        while true {
            let output = splitter.feed(chunk)
            fed += chunk.count

            if output.exceededMaximum {
                break
            }

            #expect(fed <= 4_096)
        }

        // It stopped at the first chunk that took the item past the maximum, not later.
        #expect(fed == 5 * 1_024)
        #expect(splitter.feed(chunk).exceededMaximum)
        #expect(splitter.finish().items.isEmpty)
    }

    @Test
    func splitter_withoutAMaximum_keepsEverything() {
        var splitter = ItemSplitter(delimiter: .lineBreak, maximumLength: nil)
        let output = splitter.feed(Data(repeating: UInt8(ascii: "x"), count: 100_000))

        #expect(!output.exceededMaximum)
        #expect(output.items.isEmpty)
        #expect(splitter.finish().items.first?.count == 100_000)
    }
}

private final class CancelFlag: Sendable {

    private let value = LockedValueBox(false)

    var isSet: Bool {
        value.withLockedValue { $0 }
    }

    func set() {
        value.withLockedValue { $0 = true }
    }
}
