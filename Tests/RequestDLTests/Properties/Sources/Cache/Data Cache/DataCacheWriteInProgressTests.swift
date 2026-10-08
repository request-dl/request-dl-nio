//
// See LICENSE for this package's licensing information.
//

import Crypto
import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
import struct Foundation.URL
import struct Foundation.Date
#endif

/// An entry is installed in both tiers the moment its write is allocated, so a request that
/// arrives while the first one is still writing must not be given the bytes written so far, as
/// if they were the whole response.
struct DataCacheWriteInProgressTests {

    private func makeCache(policy: DataCache.Policy.Set) -> (DataCache, String) {
        let dataCache = DataCache(
            memoryCapacity: policy.contains(.memory) ? 8 * 1_024 * 1_024 : .zero,
            diskCapacity: policy.contains(.disk) ? 8 * 1_024 * 1_024 : .zero,
            suiteName: UUID().uuidString
        )

        return (dataCache, "https://example.com/" + UUID().uuidString)
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

    // MARK: - Reading while a write is going on

    @Test(arguments: [DataCache.Policy.Set.memory, .disk])
    func getCachedData_whileTheEntryIsStillBeingWritten_isAMiss(_ policy: DataCache.Policy.Set) async throws {
        // Given: a write that has put part of its body in.
        let (dataCache, key) = makeCache(policy: policy)

        var buffer = try #require(
            await dataCache.allocateBuffer(
                key: key,
                cachedResponse: response(key, policy: policy),
                contentLength: 0
            )
        )

        await buffer.writeBuffer(await bytes(3))

        // Then: the bytes so far are not the response.
        #expect(await dataCache.getCachedData(forKey: key, policy: policy) == nil)

        // When: the rest arrives and the write is finished.
        await buffer.writeBuffer(await bytes(4))
        await dataCache.finalizeWrite(buffer, contentLengthHint: 0)

        // Then: now it is, whole.
        let cached = try #require(await dataCache.getCachedData(forKey: key, policy: policy))
        #expect(await cached.data == Data(repeating: 0x61, count: 7))
    }

    /// With an encryption key the final chunk is sealed only when the buffer is closed, so the
    /// write closes it before the entry can be read, or an entry read right after its write
    /// reads back as empty.
    @Test
    func getCachedData_afterAnEncryptedWriteIsFinished_returnsTheWholeBody() async throws {
        // Given
        let (dataCache, key) = makeCache(policy: .disk)
        dataCache.encryptionKey = DataCache.EncryptionKey(SymmetricKey(size: .bits256))

        var buffer = try #require(
            await dataCache.allocateBuffer(
                key: key,
                cachedResponse: response(key, policy: .disk),
                contentLength: 1_000
            )
        )

        // When
        await buffer.writeBuffer(bytes(1_000))
        await dataCache.finalizeWrite(buffer, contentLengthHint: 1_000)

        // Then
        let cached = try #require(await dataCache.getCachedData(forKey: key, policy: .disk))
        #expect(await cached.data.count == 1_000)
    }

    // MARK: - A write that does not finish

    @Test(arguments: [DataCache.Policy.Set.memory, .disk])
    func discardFailedWrite_liftsTheMissAndLeavesNothingBehind(_ policy: DataCache.Policy.Set) async throws {
        // Given
        let (dataCache, key) = makeCache(policy: policy)

        var failed = try #require(
            await dataCache.allocateBuffer(
                key: key,
                cachedResponse: response(key, policy: policy),
                contentLength: 0
            )
        )

        await failed.writeBuffer(await bytes(3))

        // When
        await dataCache.discardFailedWrite(failed, forKey: key)

        // Then: nothing to serve, and a later write to the same key is served once finished.
        #expect(await dataCache.getCachedData(forKey: key, policy: policy) == nil)

        var next = try #require(
            await dataCache.allocateBuffer(
                key: key,
                cachedResponse: response(key, policy: policy),
                contentLength: 0
            )
        )

        await next.writeBuffer(await bytes(5))
        await dataCache.finalizeWrite(next, contentLengthHint: 0)

        let cached = try #require(await dataCache.getCachedData(forKey: key, policy: policy))
        #expect(await cached.data == Data(repeating: 0x61, count: 5))
    }

    /// A discarded disk write removes its directory and the index entry pointing at it, or the
    /// next read of that key goes to a directory that is gone and spends the whole retry budget
    /// (up to 15s) on it.
    @Test
    func getCachedData_afterADiscardedDiskWrite_missesWithoutWaiting() async throws {
        // Given
        let (dataCache, key) = makeCache(policy: .disk)

        let failed = try #require(
            await dataCache.allocateBuffer(
                key: key,
                cachedResponse: response(key, policy: .disk),
                contentLength: 0
            )
        )

        await dataCache.discardFailedWrite(failed, forKey: key)

        // When
        let start = Date()
        let cached = await dataCache.getCachedData(forKey: key, policy: .disk)
        let elapsed = Date().timeIntervalSince(start)

        // Then
        #expect(cached == nil)
        #expect(elapsed < 5, "took \(elapsed)s")
    }

    /// Another key is not held back by a write to this one.
    @Test
    func getCachedData_forAnotherKey_isNotAffectedByAWriteInProgress() async throws {
        // Given: a finished entry, and a write going on for a different key.
        let (dataCache, finishedKey) = makeCache(policy: .memory)
        let busyKey = finishedKey + "-busy"

        await dataCache.setCachedData(
            await CachedData(
                response: ResponseHead(
                    url: URL(string: finishedKey),
                    status: .init(code: 200, reason: "OK"),
                    version: .init(minor: 1, major: 1),
                    headers: HTTPHeaders([]),
                    isKeepAlive: true
                ),
                policy: .memory,
                data: Data("done".utf8)
            ),
            forKey: finishedKey
        )

        var busy = try #require(
            await dataCache.allocateBuffer(
                key: busyKey,
                cachedResponse: response(busyKey, policy: .memory),
                contentLength: 0
            )
        )
        await busy.writeBuffer(await bytes(2))

        // Then
        let cached = try #require(await dataCache.getCachedData(forKey: finishedKey, policy: .memory))
        #expect(await cached.data == Data("done".utf8))

        await dataCache.discardFailedWrite(busy, forKey: busyKey)
    }
}
