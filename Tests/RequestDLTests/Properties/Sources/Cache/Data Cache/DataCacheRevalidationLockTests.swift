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
import struct Foundation.Date
import struct Foundation.UUID
#endif

/// Renewing a revalidated entry takes a lock so that revalidations of one entry take turns. It is
/// the entry's lock, not the cache's: an unrelated URL has nothing to wait for.
struct DataCacheRevalidationLockTests {

    private func makeCache() -> DataCache {
        DataCache(
            memoryCapacity: 8 * 1_024 * 1_024,
            diskCapacity: 8 * 1_024 * 1_024,
            suiteName: UUID().uuidString
        )
    }

    private func response(date: Date) -> CachedResponse {
        .init(
            response: .init(
                url: "https://example.com",
                status: .init(code: 200, reason: "OK"),
                version: .init(minor: 1, major: 1),
                headers: [],
                isKeepAlive: true
            ),
            policy: .memory,
            date: date
        )
    }

    private func store(_ key: String, in dataCache: DataCache) async -> CachedResponse {
        let stored = response(date: Date().addingTimeInterval(-10))

        await dataCache.setCachedData(
            CachedData(cachedResponse: stored, buffer: await Internals.DataBuffer(Data("body".utf8))),
            forKey: key
        )

        return stored
    }

    /// Holds the revalidation lock of `key` until `release` is called, and returns once it is held.
    private func hold(
        _ key: String,
        in dataCache: DataCache
    ) async throws -> (release: @Sendable () -> Void, finished: Task<Void, Never>) {
        let (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        let storage = dataCache.storage

        let finished = Task {
            await storage.withRevalidationLock(forKey: key) {
                for await _ in stream { break }
            }
        }

        try await eventually { storage.revalidationLockCount == 1 }

        return ({ continuation.yield() }, finished)
    }

    @Test
    func renewCached_whileAnotherKeyIsBeingRenewed_isNotHeldUp() async throws {
        // Given: the lock of one key is held, as it is for as long as its renewal takes.
        let dataCache = makeCache()
        let other = "https://example.com/" + UUID().uuidString
        let expected = await store(other, in: dataCache)

        let (release, finished) = try await hold("https://example.com/held", in: dataCache)

        // When: another key is renewed meanwhile.
        let renewed = try await completing(within: 5) {
            await dataCache.renewCached(
                key: other,
                cachedResponse: self.response(date: Date()),
                expecting: expected,
                policy: .memory
            )
        }

        // Then: it did not wait for the first one.
        #expect(renewed != nil)

        release()
        await finished.value
    }

    @Test
    func renewCached_whileTheSameKeyIsBeingRenewed_waitsForIt() async throws {
        // Given
        let dataCache = makeCache()
        let key = "https://example.com/" + UUID().uuidString
        let expected = await store(key, in: dataCache)

        let (release, finished) = try await hold(key, in: dataCache)
        let finishedRenewal = LockedValueBox(false)
        let renewal = Task {
            let renewed = await dataCache.renewCached(
                key: key,
                cachedResponse: self.response(date: Date()),
                expecting: expected,
                policy: .memory
            )

            finishedRenewal.withLockedValue { $0 = true }
            return renewed
        }

        // Then: it is still waiting while the lock is held, and goes through once it is not.
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(finishedRenewal.withLockedValue { $0 } == false)

        release()
        await finished.value

        #expect(await renewal.value != nil)
    }

    @Test
    func renewCached_whenFinished_leavesNoLockBehind() async throws {
        // Given
        let dataCache = makeCache()
        let key = "https://example.com/" + UUID().uuidString
        let expected = await store(key, in: dataCache)

        // When
        _ = await dataCache.renewCached(
            key: key,
            cachedResponse: response(date: Date()),
            expecting: expected,
            policy: .memory
        )

        // Then: a lock per URL ever revalidated would be a leak.
        #expect(dataCache.storage.revalidationLockCount == 0)
    }
}
