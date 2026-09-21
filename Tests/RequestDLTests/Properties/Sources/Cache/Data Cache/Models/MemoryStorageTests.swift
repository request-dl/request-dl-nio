//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
#endif

struct MemoryStorageTests {

    private func makeCachedResponse(key: String) -> CachedResponse {
        CachedResponse(
            response: .init(
                url: "https://www.apple.com/\(key)",
                status: .init(code: 200, reason: "OK"),
                version: .init(minor: 0, major: 1),
                headers: [],
                isKeepAlive: true
            ),
            policy: .all
        )
    }

    @Test
    func freeSpace_whenKnownUsageFitsUnderCapacity_shouldSkipRescanAndKeepEverything() async throws {
        var storage = MemoryStorage(directory: URL(filePath: "/tmp"))

        // Given: a real entry that is already over whatever capacity `freeSpace` is about to be
        // called with — a rescan would find it and evict it.
        let (dataURL, _) = storage.allocateBuffer(
            key: "k1",
            cachedResponse: makeCachedResponse(key: "k1"),
            contentLength: 1,
            maximumCapacity: .max
        )
        let dataURL0 = try #require(dataURL)
        dataURL0.replace(with: Data([0x1]))

        // When: freeing space down to zero, but with a `knownUsage` of zero — a trusted (if,
        // here, deliberately wrong) claim that there is nothing to evict.
        let result = storage.freeSpace(.zero, knownUsage: .zero)

        // Then: the rescan was skipped on the strength of that claim, so the entry survives, and
        // the call reports back exactly the `knownUsage` it was given.
        #expect(result == .zero)
        #expect(await storage["k1"] != nil)
    }

    @Test
    func freeSpace_whenKnownUsageExceedsCapacity_shouldRescanAndEvict() async throws {
        var storage = MemoryStorage(directory: URL(filePath: "/tmp"))

        let (dataURL, _) = storage.allocateBuffer(
            key: "k1",
            cachedResponse: makeCachedResponse(key: "k1"),
            contentLength: 4,
            maximumCapacity: .max
        )
        #expect(dataURL != nil)

        // When: `knownUsage` itself already claims to be over capacity, so the shortcut cannot
        // apply and the real scan below has to run.
        let result = storage.freeSpace(.zero, knownUsage: .max)

        // Then: the real scan found and evicted the entry, and reported the true resulting
        // total — zero, since it was the only entry — rather than the stale `knownUsage`.
        #expect(result == .zero)
        #expect(await storage["k1"] == nil)
    }

    @Test
    func allocateBuffer_shouldReturnUsageReflectingTheNewEntry() {
        var storage = MemoryStorage(directory: URL(filePath: "/tmp"))

        // Given/When: the first entry in an empty store, so usage after it is exactly its own
        // content length.
        let (_, firstUsage) = storage.allocateBuffer(
            key: "k1",
            cachedResponse: makeCachedResponse(key: "k1"),
            contentLength: 10,
            maximumCapacity: .max
        )
        #expect(firstUsage == 10)

        // When: a second entry is allocated reusing that reported usage as `knownUsage` — the
        // shape `DataCache.Storage` relies on to thread the estimate across calls.
        let (_, secondUsage) = storage.allocateBuffer(
            key: "k2",
            cachedResponse: makeCachedResponse(key: "k2"),
            contentLength: 20,
            maximumCapacity: .max,
            knownUsage: firstUsage
        )

        // Then: usage accumulates exactly, with no rescan needed in between.
        #expect(secondUsage == 30)
    }

    /// Regression coverage for the memory-tier race `DataCache.discardFailedWrite` used to be
    /// exposed to: a plain `remove(_:)` deletes whatever record currently sits at `key`, even
    /// one a concurrent write installed after the caller's own record was replaced.
    @Test
    func remove_ifDataURL_whenRecordWasReplaced_shouldLeaveTheReplacementInPlace() async throws {
        var storage = MemoryStorage(directory: URL(filePath: "/tmp"))

        let (firstDataURL, _) = storage.allocateBuffer(
            key: "k1",
            cachedResponse: makeCachedResponse(key: "k1"),
            contentLength: 0,
            maximumCapacity: .max
        )
        let firstDataURL0 = try #require(firstDataURL)

        // A second allocation for the same key installs a fresh record with its own `dataURL`,
        // simulating a concurrent write to the same key winning the race.
        let (secondDataURL, _) = storage.allocateBuffer(
            key: "k1",
            cachedResponse: makeCachedResponse(key: "k1"),
            contentLength: 0,
            maximumCapacity: .max
        )
        let secondDataURL0 = try #require(secondDataURL)
        #expect(firstDataURL0 !== secondDataURL0)

        // When: the first write's cleanup runs, targeting the record it originally allocated.
        storage.remove("k1", ifDataURL: firstDataURL0)

        // Then: the second write's record — the current one — is untouched.
        #expect(await storage["k1"] != nil)
    }

    @Test
    func remove_ifDataURL_whenRecordStillMatches_shouldRemoveIt() async throws {
        var storage = MemoryStorage(directory: URL(filePath: "/tmp"))

        let (dataURL, _) = storage.allocateBuffer(
            key: "k1",
            cachedResponse: makeCachedResponse(key: "k1"),
            contentLength: 0,
            maximumCapacity: .max
        )
        let dataURL0 = try #require(dataURL)

        storage.remove("k1", ifDataURL: dataURL0)

        #expect(await storage["k1"] == nil)
    }
}
