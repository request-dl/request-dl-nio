//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import SwiftAsyncStream
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct AsyncBytesEventsTests {

    @Test
    func events_whenBytesArriveSplitAcrossChunks_shouldYieldParsedEvents() async throws {
        // Given
        let stream = Internals.AsyncStream<Internals.DataBuffer>()

        let part1 = Data("id: 1\nevent: greeting\ndata: hel".utf8)
        let part2 = Data("lo\n\nretry: 2000\ndata: world\n\n".utf8)

        let internalBytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: part1.count + part2.count,
            stream: stream
        )

        let bytes = AsyncBytes(seed: .withoutCancellation, bytes: internalBytes)

        // When
        await stream.append(.success(Internals.DataBuffer(part1)))
        await stream.append(.success(Internals.DataBuffer(part2)))
        stream.close()

        var events: [ServerSentEvent] = []

        for try await event in bytes.events() {
            events.append(event)
        }

        // Then
        #expect(
            events == [
                ServerSentEvent(id: "1", event: "greeting", data: "hello", retry: nil),
                ServerSentEvent(id: "1", event: "message", data: "world", retry: 2000),
            ]
        )
    }

    @Test
    func events_whenStreamEndsWithoutTrailingBlankLine_shouldStillYieldLastEvent() async throws {
        // Given
        let stream = Internals.AsyncStream<Internals.DataBuffer>()
        let part = Data("data: hello".utf8)

        let internalBytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: part.count,
            stream: stream
        )

        let bytes = AsyncBytes(seed: .withoutCancellation, bytes: internalBytes)

        // When
        await stream.append(.success(Internals.DataBuffer(part)))
        stream.close()

        var events: [ServerSentEvent] = []

        for try await event in bytes.events() {
            events.append(event)
        }

        // Then
        #expect(
            events == [
                ServerSentEvent(id: nil, event: "message", data: "hello", retry: nil)
            ]
        )
    }

    @Test
    func events_whenALineOutgrowsTheMaximum_failsAfterTheEarlierEvents() async throws {
        // Given: one complete event, then a line that never ends.
        let stream = Internals.AsyncStream<Internals.DataBuffer>()
        let parts = [
            Data("data: first\n\n".utf8),
            Data("data: ".utf8),
            Data(String(repeating: "x", count: 2_000).utf8),
            Data(String(repeating: "x", count: 2_000).utf8),
        ]

        let internalBytes = Internals.AsyncBytes(
            logger: nil,
            totalSize: parts.reduce(0) { $0 + $1.count },
            stream: stream
        )
        let bytes = AsyncBytes(seed: .withoutCancellation, bytes: internalBytes)

        for part in parts {
            await stream.append(.success(Internals.DataBuffer(part)))
        }

        stream.close()

        // When/Then
        var iterator = bytes.events(maximumLineLength: 1_000).makeAsyncIterator()

        #expect(try await iterator.next()?.data == "first")

        await #expect(throws: AsyncBytesItemTooLargeError(maximumLength: 1_000)) {
            _ = try await iterator.next()
        }

        #expect(try await iterator.next() == nil)
    }

    @Test
    func events_whenTheLastLineWithoutABreakOutgrowsTheMaximum_fails() async throws {
        let stream = Internals.AsyncStream<Internals.DataBuffer>()
        let part = Data("data: 0123456789".utf8)

        let internalBytes = Internals.AsyncBytes(logger: nil, totalSize: part.count, stream: stream)
        let bytes = AsyncBytes(seed: .withoutCancellation, bytes: internalBytes)

        await stream.append(.success(Internals.DataBuffer(part)))
        stream.close()

        await #expect(throws: AsyncBytesItemTooLargeError(maximumLength: 10)) {
            for try await _ in bytes.events(maximumLineLength: 10) {}
        }
    }

    @Test
    func events_withoutAMaximum_stillReadsAVeryLongLine() async throws {
        let stream = Internals.AsyncStream<Internals.DataBuffer>()
        let payload = String(repeating: "x", count: 200_000)
        let part = Data("data: \(payload)\n\n".utf8)

        let internalBytes = Internals.AsyncBytes(logger: nil, totalSize: part.count, stream: stream)
        let bytes = AsyncBytes(seed: .withoutCancellation, bytes: internalBytes)

        await stream.append(.success(Internals.DataBuffer(part)))
        stream.close()

        var events: [ServerSentEvent] = []

        for try await event in bytes.events() {
            events.append(event)
        }

        #expect(events.map(\.data) == [payload])
    }
}
