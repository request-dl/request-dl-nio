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
}
