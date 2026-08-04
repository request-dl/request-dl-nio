//
// See LICENSE for this package's licensing information.
//

import AsyncAlgorithms
import SwiftAsyncStream
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
// import struct Foundation.UUID
// import struct Foundation.Date
// import struct Foundation.URL
#endif

private let globalMemoryCapacity: Int64 = 8 * 1_024 * 1_024
private let globalDiskCapacity: Int64 = 64 * 1_024 * 1_024
private let globalDataCache = DataCache(suiteName: UUID().uuidString)

@Suite(.serialized)
struct DataCacheTests {

    final class TestState: Sendable {

        let dataCache: DataCache

        /// ## Cleaning up front instead of in `deinit`
        ///
        /// Every test in this suite points at `globalDataCache.directoryURL`, so they all read
        /// and write the same directory. That makes teardown ordering load bearing, and `deinit`
        /// cannot carry it: `removeAll()` is asynchronous, `deinit` cannot suspend, and a
        /// detached task is not ordered against the end of the test. Zeroing the capacities had
        /// the same problem from the other direction, since the disk setter hands its eviction
        /// to the cache's pending-writes tracker rather than awaiting it.
        ///
        /// Both were therefore firing destructive work at the shared directory at some
        /// unspecified later moment, which landed in the middle of whichever test ran next.
        /// That is what made `cache_whenSetCachedData` fail on `cachedDisk1` sometimes and
        /// `cachedDisk2` other times: the two keys are written and read in sequence, so a stray
        /// wipe catches whichever one it happens to overlap.
        ///
        /// Cleaning at setup is awaited, always runs, and does not depend on the previous test
        /// having torn itself down properly, which is the point: a test that crashes or is
        /// cancelled never runs its teardown at all.
        ///
        /// The capacities need no resetting. Constructing over an existing storage raises the
        /// capacity to the larger of the two, which
        /// `cache_whenInitWithLowerCapacityPreviousSpecified` asserts on purpose, so building
        /// with the globals is already the reset.
        init() async {
            dataCache = .init(
                memoryCapacity: globalMemoryCapacity,
                diskCapacity: globalDiskCapacity,
                url: globalDataCache.directoryURL
            )

            await dataCache.removeAll()

            // Joins any eviction the capacity setter queued, so the directory is known to be
            // empty before the test writes its first entry.
            await dataCache.waitUntilIdle()
        }
    }

    @Test
    func cache_whenInit_shouldCapacityBeKnown() async throws {
        let testState = await TestState()
        // Given
        let dataCache = testState.dataCache

        // Then
        #expect(dataCache.memoryCapacity == globalMemoryCapacity)
        #expect(dataCache.diskCapacity == globalDiskCapacity)
    }

    @Test
    func cache_whenInitWithLowerCapacityPreviousSpecified_shouldBeMax() async {
        let testState = await TestState()
        defer { _ = testState }
        // Given
        let memoryCapacity: Int64 = 4 * 1_024 * 1_024
        let diskCapacity: Int64 = 16 * 1_024 * 1_024

        // When
        let dataCache = DataCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            url: globalDataCache.directoryURL
        )

        // Then
        #expect(dataCache.memoryCapacity == globalMemoryCapacity)
        #expect(dataCache.diskCapacity == globalDiskCapacity)
    }

    @Test
    func cache_whenSetCapacityDirectly_shouldBeValid() async throws {
        let testState = await TestState()
        // Given
        let dataCache = testState.dataCache

        let memoryCapacity: Int64 = 4 * 1_024 * 1_024
        let diskCapacity: Int64 = 16 * 1_024 * 1_024

        // When
        dataCache.memoryCapacity = memoryCapacity
        dataCache.diskCapacity = diskCapacity

        // Then
        #expect(dataCache.memoryCapacity == memoryCapacity)
        #expect(dataCache.diskCapacity == diskCapacity)
    }

    @Test
    func cache_whenSetCachedData() async throws {
        let testState = await TestState()
        defer { _ = testState }
        // Given
        let dataCache = testState.dataCache

        let key1 = "https://google.com"
        let key2 = "https://apple.com"

        let data1 = await Data.randomData(length: 1_024)
        let data2 = await Data.randomData(length: 8 * 1_024)

        // When
        for (key, data) in [(key1, data1), (key2, data2)] {
            await dataCache.setCachedData(
                CachedData(
                    response: mockResponse(url: key),
                    policy: .all,
                    data: data
                ),
                forKey: key
            )
        }

        let cachedMemory1 = await dataCache.getCachedData(forKey: key1, policy: .memory)
        let cachedDisk1 = await dataCache.getCachedData(forKey: key1, policy: .disk)

        let cachedMemory2 = await dataCache.getCachedData(forKey: key2, policy: .memory)
        let cachedDisk2 = await dataCache.getCachedData(forKey: key2, policy: .disk)

        // Then
        let cachedMemory1Data = await cachedMemory1?.data
        #expect(cachedMemory1Data == data1)
        let cachedDisk1Data = await cachedDisk1?.data
        #expect(cachedDisk1Data == data1)

        let cachedMemory2Data = await cachedMemory2?.data
        #expect(cachedMemory2Data == data2)
        let cachedDisk2Data = await cachedDisk2?.data
        #expect(cachedDisk2Data == data2)
    }

    @Test
    func cache_whenLowMemory() async throws {
        let testState = await TestState()
        // Given
        let dataCache = testState.dataCache

        dataCache.memoryCapacity = 1_024

        let key1 = "https://google.com"
        let key2 = "https://apple.com"

        let cachedData1 = await mockCachedData(
            url: key1,
            length: 1_024 - 256,
            policy: .memory
        )

        let cachedData2 = await mockCachedData(
            url: key2,
            length: 512,
            policy: .memory
        )

        // When
        await dataCache.setCachedData(cachedData1, forKey: key1)
        await dataCache.setCachedData(cachedData2, forKey: key2)

        let cachedMemory1 = await dataCache.getCachedData(forKey: key1, policy: .memory)
        let cachedMemory2 = await dataCache.getCachedData(forKey: key2, policy: .memory)

        // Then
        #expect(cachedMemory1 == nil)

        // Extracted first: comparing two `async` property accesses directly inside `#expect`
        // fails to compile ("'async' property access in an autoclosure that does not support
        // concurrency") even with `await` on the macro call itself.
        let cachedData2Bytes = await cachedData2.data
        let cachedMemory2Data = await cachedMemory2?.data
        #expect(cachedMemory2Data == cachedData2Bytes)
    }

    @Test
    func cache_whenLowDisk() async throws {
        let testState = await TestState()
        defer { _ = testState }
        // Given
        let dataCache = testState.dataCache

        dataCache.diskCapacity = 1_024

        await dataCache.waitUntilIdle()

        let key1 = "https://google.com"
        let key2 = "https://apple.com"

        let cachedData1 = await mockCachedData(
            url: key1,
            length: 1_024 - 256,
            policy: .disk
        )

        let cachedData2 = await mockCachedData(
            url: key2,
            length: 512,
            policy: .disk
        )

        // When
        await dataCache.setCachedData(cachedData1, forKey: key1)
        await dataCache.setCachedData(cachedData2, forKey: key2)

        let cachedDisk1 = await dataCache.getCachedData(forKey: key1, policy: .disk)
        let cachedDisk2 = await dataCache.getCachedData(forKey: key2, policy: .disk)

        // Then
        #expect(cachedDisk1 == nil)

        let cachedData2Bytes = await cachedData2.data
        let cachedDisk2Data = await cachedDisk2?.data
        #expect(cachedDisk2Data == cachedData2Bytes)
    }

    @Test
    func cache_whenRemoveKey() async throws {
        let testState = await TestState()
        defer { _ = testState }

        // Given
        let dataCache = testState.dataCache

        let key1 = "https://google.com"
        let key2 = "https://apple.com"

        let cachedData1 = await mockCachedData(
            url: key1,
            length: 1_024 - 256
        )

        let cachedData2 = await mockCachedData(
            url: key2,
            length: 512
        )

        // When
        await dataCache.setCachedData(cachedData1, forKey: key1)
        await dataCache.setCachedData(cachedData2, forKey: key2)

        let memoryCached1 = await dataCache.getCachedData(forKey: key1, policy: .memory)
        let diskCached1 = await dataCache.getCachedData(forKey: key1, policy: .disk)
        let diskCached1Data = await diskCached1?.data

        await dataCache.remove(forKey: key1)

        let memoryCached2 = await dataCache.getCachedData(forKey: key2, policy: .memory)
        let diskCached2 = await dataCache.getCachedData(forKey: key2, policy: .disk)

        let memoryCached1_v2 = await dataCache.getCachedData(forKey: key1, policy: .memory)
        let diskCached1_v2 = await dataCache.getCachedData(forKey: key1, policy: .disk)

        // Then
        let cachedData1Bytes = await cachedData1.data
        let cachedData2Bytes = await cachedData2.data

        let memoryCached1Data = await memoryCached1?.data
        #expect(memoryCached1Data == cachedData1Bytes)
        #expect(diskCached1Data == cachedData1Bytes)

        let memoryCached2Data = await memoryCached2?.data
        #expect(memoryCached2Data == cachedData2Bytes)
        let diskCached2Data = await diskCached2?.data
        #expect(diskCached2Data == cachedData2Bytes)

        #expect(memoryCached1_v2 == nil)
        #expect(diskCached1_v2 == nil)
    }

    @Test
    func cache_whenRemoveSince() async throws {
        let testState = await TestState()
        // Given
        let dataCache = testState.dataCache

        let cachedDatas = try await Array(
            (0..<3).async.map {
                await mockCachedData(
                    url: "https://google.com/\($0)",
                    length: 1_024
                )
            }
        )

        // When
        for cacheData in cachedDatas {
            await dataCache.setCachedData(cacheData, forKey: cacheData.cachedResponse.response.url)
        }

        await dataCache.removeAll(since: cachedDatas[1].cachedResponse.date)

        let storedDatas = try await Array(
            [0, 1, 2].async.map {
                await dataCache.getCachedData(forKey: "https://google.com/\($0)", policy: .all)
            }
        )

        // Then
        #expect(storedDatas[0] == nil)
        #expect(storedDatas[1] == nil)

        let cachedData2Bytes = await cachedDatas[2].data
        let storedData2 = await storedDatas[2]?.data
        #expect(storedData2 == cachedData2Bytes)
    }

    @Test
    func cache_whenRemoveAll() async throws {
        let testState = await TestState()
        // Given
        let dataCache = testState.dataCache

        let cachedDatas = try await Array(
            (0..<3).async.map {
                await mockCachedData(
                    url: "https://google.com/\($0)",
                    length: 1_024
                )
            }
        )

        // When
        for cacheData in cachedDatas {
            await dataCache.setCachedData(cacheData, forKey: cacheData.cachedResponse.response.url)
        }

        await dataCache.removeAll()

        let storedDatas = try await Array(
            [0, 1, 2].async.map {
                await dataCache.getCachedData(forKey: "https://google.com/\($0)", policy: .all)
            }
        )

        // Then
        #expect(storedDatas[0] == nil)
        #expect(storedDatas[1] == nil)
        #expect(storedDatas[2] == nil)
    }

    @Test
    func cache_whenEntryExceedsMemoryAndDiskCapacity_shouldNotBeCached() async throws {
        let testState = await TestState()
        // Given
        let dataCache = testState.dataCache

        dataCache.memoryCapacity = 512
        dataCache.diskCapacity = 512
        await dataCache.waitUntilIdle()

        let key = "https://oversized.example.com"

        let cachedData = await mockCachedData(
            url: key,
            length: 1_024,
            policy: .all
        )

        // When
        await dataCache.setCachedData(cachedData, forKey: key)
        await dataCache.waitUntilIdle()

        // Then
        let cached = await dataCache.getCachedData(forKey: key, policy: .all)
        #expect(cached == nil)
    }

    @Test
    func cache_whenUpdateCachedForExistingKey_shouldReplaceMetadataAndKeepBuffer() async throws {
        let testState = await TestState()
        // Given
        let dataCache = testState.dataCache

        let key = "https://updatable.example.com"
        let cachedData = await mockCachedData(url: key, length: 128, policy: .memory)

        await dataCache.setCachedData(cachedData, forKey: key)

        let newCachedResponse = await mockCachedData(
            url: key,
            length: 32,
            policy: .memory
        ).cachedResponse

        // When
        await dataCache.updateCached(key: key, cachedResponse: newCachedResponse)

        // Then
        let cachedMemory = await dataCache.getCachedData(forKey: key, policy: .memory)
        #expect(cachedMemory != nil)
        #expect(await cachedMemory?.data == cachedData.data)
    }

    @Test
    func cache_whenUpdateCachedOnDiskForExistingKey_shouldReplaceMetadataAndKeepBuffer() async throws {
        let testState = await TestState()
        // Given
        let dataCache = testState.dataCache

        let key = "https://updatable-disk.example.com"
        let cachedData = await mockCachedData(url: key, length: 128, policy: .disk)

        await dataCache.setCachedData(cachedData, forKey: key)

        let newCachedResponse = await mockCachedData(
            url: key,
            length: 32,
            policy: .disk
        ).cachedResponse

        // When
        await dataCache.updateCached(key: key, cachedResponse: newCachedResponse)

        // Then
        let cachedDisk = await dataCache.getCachedData(forKey: key, policy: .disk)
        #expect(cachedDisk != nil)
        #expect(await cachedDisk?.data == cachedData.data)
    }

    @Test
    func cache_whenUpdateCachedOnDiskForMissingKey_shouldDoNothing() async throws {
        let testState = await TestState()
        // Given
        let dataCache = testState.dataCache

        let key = "https://never-allocated-disk.example.com"

        let cachedResponse = await mockCachedData(
            url: key,
            length: 32,
            policy: .disk
        ).cachedResponse

        // When
        await dataCache.updateCached(key: key, cachedResponse: cachedResponse)

        // Then
        let cachedDisk = await dataCache.getCachedData(forKey: key, policy: .disk)
        #expect(cachedDisk == nil)
    }

    @Test
    func cache_whenUpdateCachedForMissingKey_shouldDoNothing() async throws {
        let testState = await TestState()
        // Given
        let dataCache = testState.dataCache

        let key = "https://never-allocated.example.com"

        let cachedResponse = await mockCachedData(
            url: key,
            length: 32,
            policy: .memory
        ).cachedResponse

        // When
        await dataCache.updateCached(key: key, cachedResponse: cachedResponse)

        // Then
        let cachedMemory = await dataCache.getCachedData(forKey: key, policy: .memory)
        #expect(cachedMemory == nil)
    }

    @Test
    func cache_whenInitWithSuiteName() {
        // Given
        let suiteName = "shared_other_lib"

        // When
        let dataCache = DataCache(suiteName: suiteName)

        let suiteURL = DataCache.temporaryURL(suiteName: suiteName)

        // Then
        #expect(dataCache == DataCache(url: suiteURL))
    }
}

extension DataCacheTests {

    func mockResponse(url: String, expiresAt expirationDate: Date = .distantFuture) -> ResponseHead {
        ResponseHead(
            url: URL(string: url),
            status: .init(code: 200, reason: "Ok"),
            version: .init(minor: 1, major: 2),
            headers: HTTPHeaders([
                ("Expires", expirationDate.toHTTPDateString()),
                ("ETag", "\(UUID())"),
            ]),
            isKeepAlive: false
        )
    }

    func mockCachedData(
        url: String,
        length: Int,
        policy: DataCache.Policy.Set = .all,
        expiresAt expirationDate: Date = .distantFuture
    ) async -> CachedData {
        await CachedData(
            response: mockResponse(url: url, expiresAt: expirationDate),
            policy: policy,
            data: Data.randomData(length: length)
        )
    }
}

extension DataCacheTests {

    @Test
    func accessingAllocateBufferMultipleTimes() async throws {
        let dataCache = DataCache(
            memoryCapacity: 100 * 1_024 * 1_024,
            suiteName: UUID().uuidString
        )

        let key = UUID().uuidString
        var locks = [AsyncSignal]()

        for index in 0..<1_000 {
            let lock = AsyncSignal()
            locks.append(lock)

            Task.detached(priority: .background) {
                defer { lock.signal() }

                _ = await dataCache.allocateBuffer(
                    key: key + "\(index)",
                    cachedResponse: .init(
                        response: .init(
                            url: UUID().uuidString,
                            status: .init(code: 200, reason: UUID().uuidString),
                            version: .init(minor: 0, major: 10),
                            headers: .init(),
                            isKeepAlive: false
                        ),
                        policy: .memory
                    ),
                    contentLength: 1_024 * 1_024
                )
            }
        }

        for lock in locks {
            try await lock.wait()
        }
    }
}
