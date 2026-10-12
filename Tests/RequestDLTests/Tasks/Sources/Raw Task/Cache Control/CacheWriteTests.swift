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
import struct Foundation.UUID
#endif

/// The chunks of a response reach the cache through a stream that is read by one task, which
/// writes them to the tiers. That stream keeps whatever the task has not read yet, so a task
/// that goes on reading a body nobody keeps any more only lets the rest pile up behind it.
struct CacheWriteTests {

    private let chunk = 1_024

    private func makeCache(memoryCapacity: Int64) -> (DataCache, String) {
        let dataCache = DataCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: .zero,
            suiteName: UUID().uuidString
        )

        return (dataCache, "https://example.com/" + UUID().uuidString)
    }

    private func response(_ key: String) -> CachedResponse {
        .init(
            response: .init(
                url: key,
                status: .init(code: 200, reason: "OK"),
                version: .init(minor: 1, major: 1),
                headers: [],
                isKeepAlive: true
            ),
            policy: .memory
        )
    }

    /// A stream with `count` chunks of one kilobyte already in it, closed, and the window that
    /// counts what is still waiting in it.
    private func makeStream(
        count: Int
    ) async -> (Internals.AsyncStream<Internals.DataBuffer>, Internals.FlowControlWindow) {
        let window = Internals.FlowControlWindow()
        let stream = Internals.AsyncStream<Internals.DataBuffer>(flowControl: window)

        for _ in 0..<count {
            stream.append(.success(await Internals.DataBuffer(Data(repeating: 0x61, count: chunk))))
        }

        stream.close()

        return (stream, window)
    }

    @Test
    func write_whenTheBodyFits_writesAllOfIt() async throws {
        // Given: room for ten chunks and a body of three.
        let (dataCache, key) = makeCache(memoryCapacity: Int64(10 * chunk))
        var buffer = try #require(
            await dataCache.allocateBuffer(key: key, cachedResponse: response(key), contentLength: 0)
        )
        let (stream, window) = await makeStream(count: 3)

        // When
        try await Internals.CacheControl.write(stream, to: &buffer)

        // Then
        #expect(buffer.readableBytes == 3 * chunk)
        #expect(window.bufferedBytesForTesting == 0)
    }

    @Test
    func write_whenEveryTierHasGivenUp_stopsReadingTheStream() async throws {
        // Given: room for four chunks and a body of a hundred.
        let (dataCache, key) = makeCache(memoryCapacity: Int64(4 * chunk))
        var buffer = try #require(
            await dataCache.allocateBuffer(key: key, cachedResponse: response(key), contentLength: 0)
        )
        let (stream, window) = await makeStream(count: 100)

        // When
        try await Internals.CacheControl.write(stream, to: &buffer)

        // Then: the tier was given up on, and the chunks after that one were not read, so they are
        // not held, copied and thrown away one by one behind the download.
        #expect(buffer.memoryOverflowed)
        #expect(window.bufferedBytesForTesting > 90 * chunk)
    }

    @Test
    func write_whenTheTierHasNoRoomAtAll_givesUpOnTheFirstChunk() async throws {
        // Given: a tier with no capacity, which is allocated and outgrown by the first chunk.
        let (dataCache, key) = makeCache(memoryCapacity: .zero)
        var buffer = try #require(
            await dataCache.allocateBuffer(key: key, cachedResponse: response(key), contentLength: 0)
        )
        let (stream, window) = await makeStream(count: 100)

        // When
        try await Internals.CacheControl.write(stream, to: &buffer)

        // Then: one chunk was read to find that out, and no other.
        #expect(buffer.memoryOverflowed)
        #expect(window.bufferedBytesForTesting == 99 * chunk)
    }

    @Test
    func write_whenThereWasNoTierToBeginWith_readsNothing() async throws {
        // Given
        var buffer = DataCache.Buffer(memoryBuffer: nil, diskBuffer: nil)
        let (stream, window) = await makeStream(count: 100)

        // When
        try await Internals.CacheControl.write(stream, to: &buffer)

        // Then
        #expect(window.bufferedBytesForTesting == 100 * chunk)
    }
}
