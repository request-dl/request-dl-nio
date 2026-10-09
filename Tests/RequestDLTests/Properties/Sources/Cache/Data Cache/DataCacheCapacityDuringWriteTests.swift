//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
#endif

/// A tier admits a write by its `Content-Length` hint, which is 0 for a chunked response, so it
/// must also stop a write whose body outgrows the capacity, or a response far larger than the
/// cache stays in memory (or on disk) until a later write evicts it.
struct DataCacheCapacityDuringWriteTests {

    private static let capacity: Int64 = 1_024

    private func makeCache(
        memory: Int64 = .zero,
        disk: Int64 = .zero
    ) -> (DataCache, String) {
        (
            DataCache(memoryCapacity: memory, diskCapacity: disk, suiteName: UUID().uuidString),
            "https://example.com/" + UUID().uuidString
        )
    }

    private func response(_ key: String, policy: DataCache.Policy.Set) -> CachedResponse {
        .init(
            response: .init(
                url: key,
                status: .init(code: 200, reason: "OK"),
                version: .init(minor: 1, major: 1),
                headers: [],
                isKeepAlive: true
            ),
            policy: policy
        )
    }

    private func bytes(_ count: Int) async -> Internals.AnyBuffer {
        await Internals.DataBuffer(Data(repeating: 0x61, count: count))
    }

    /// Writes `chunks` pieces of `size` bytes through a fresh write for `key`, as a chunked
    /// response would (`contentLength: 0`), and finishes it.
    private func write(
        _ dataCache: DataCache,
        key: String,
        policy: DataCache.Policy.Set,
        chunks: Int,
        size: Int
    ) async throws {
        var buffer = try #require(
            await dataCache.allocateBuffer(
                key: key,
                cachedResponse: response(key, policy: policy),
                contentLength: 0
            )
        )

        for _ in 0..<chunks {
            await buffer.writeBuffer(await bytes(size))
        }

        await dataCache.finalizeWrite(buffer, contentLengthHint: 0)
    }

    // MARK: - One tier

    @Test(arguments: [DataCache.Policy.Set.memory, .disk])
    func write_whenTheBodyOutgrowsTheTierWithoutAContentLength_isNotKept(_ policy: DataCache.Policy.Set) async throws {
        // Given
        let (dataCache, key) = makeCache(
            memory: policy.contains(.memory) ? Self.capacity : .zero,
            disk: policy.contains(.disk) ? Self.capacity : .zero
        )

        // When: 4 KiB through a tier of 1 KiB.
        try await write(dataCache, key: key, policy: policy, chunks: 8, size: 512)

        // Then
        #expect(await dataCache.getCachedData(forKey: key, policy: policy) == nil)
    }

    @Test(arguments: [DataCache.Policy.Set.memory, .disk])
    func write_whenTheBodyFitsTheTier_isKept(_ policy: DataCache.Policy.Set) async throws {
        // Given: room for the body and the record that describes it.
        let (dataCache, key) = makeCache(
            memory: policy.contains(.memory) ? 4 * Self.capacity : .zero,
            disk: policy.contains(.disk) ? 4 * Self.capacity : .zero
        )

        // When
        try await write(dataCache, key: key, policy: policy, chunks: 2, size: 512)

        // Then
        let cached = try #require(await dataCache.getCachedData(forKey: key, policy: policy))
        #expect(await cached.data.count == 1_024)
    }

    /// A write that outgrew its tier must not leave the tracked usage counting bytes that are not
    /// there, or later writes would be turned away for room that is free.
    @Test(arguments: [DataCache.Policy.Set.memory, .disk])
    func write_afterOneThatOutgrewTheTier_isStillAdmitted(_ policy: DataCache.Policy.Set) async throws {
        // Given
        let (dataCache, key) = makeCache(
            memory: policy.contains(.memory) ? 4 * Self.capacity : .zero,
            disk: policy.contains(.disk) ? 4 * Self.capacity : .zero
        )

        try await write(dataCache, key: key, policy: policy, chunks: 40, size: 512)
        #expect(await dataCache.getCachedData(forKey: key, policy: policy) == nil)

        // When
        let other = key + "-other"
        try await write(dataCache, key: other, policy: policy, chunks: 2, size: 512)

        // Then
        let cached = try #require(await dataCache.getCachedData(forKey: other, policy: policy))
        #expect(await cached.data.count == 1_024)
    }

    // MARK: - Both tiers

    /// The tier that still has room keeps the entry, and the one that was outgrown lets it go.
    @Test
    func write_whenOnlyTheMemoryTierIsOutgrown_theDiskTierKeepsTheEntry() async throws {
        // Given: 1 KiB of memory, plenty of disk.
        let (dataCache, key) = makeCache(memory: Self.capacity, disk: 64 * Self.capacity)

        // When
        try await write(dataCache, key: key, policy: .all, chunks: 8, size: 512)

        // Then
        #expect(await dataCache.getCachedData(forKey: key, policy: .memory) == nil)

        let cached = try #require(await dataCache.getCachedData(forKey: key, policy: .disk))
        #expect(await cached.data.count == 4_096)
    }
}
