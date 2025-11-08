/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

private let globalMemoryCapacity: UInt64 = 8 * 1_024 * 1_024
private let globalDiskCapacity: UInt64 = 64 * 1_024 * 1_024

@Suite(.localDataCache)
struct DataCacheTests {

    final class TestState: Sendable {

        let suiteName = UUID().uuidString
        let globalDataCache: DataCache
        let dataCache: DataCache

        init() {
            globalDataCache = DataCache(suiteName: suiteName)

            dataCache = .init(
                memoryCapacity: globalMemoryCapacity,
                diskCapacity: globalDiskCapacity,
                suiteName: suiteName
            )
        }

        deinit {
            dataCache.removeAll()
            globalDataCache.memoryCapacity = .zero
            globalDataCache.diskCapacity = .zero
        }
    }

    @Test
    func cache_whenInit_shouldCapacityBeKnown() throws {
        let testState = TestState()
        // Given
        let dataCache = testState.dataCache

        // Then
        #expect(dataCache.memoryCapacity == globalMemoryCapacity)
        #expect(dataCache.diskCapacity == globalDiskCapacity)
    }

    @Test
    func cache_whenInitWithLowerCapacityPreviousSpecified_shouldBeMax() {
        let testState = TestState()
        defer { _ = testState }
        // Given
        let memoryCapacity: UInt64 = 4 * 1_024 * 1_024
        let diskCapacity: UInt64 = 16 * 1_024 * 1_024

        // When
        let dataCache = DataCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            suiteName: testState.suiteName
        )

        // Then
        #expect(dataCache.memoryCapacity == globalMemoryCapacity)
        #expect(dataCache.diskCapacity == globalDiskCapacity)
    }

    @Test
    func cache_whenSetCapacityDirectly_shouldBeValid() throws {
        let testState = TestState()
        // Given
        let dataCache = testState.dataCache

        let memoryCapacity: UInt64 = 4 * 1_024 * 1_024
        let diskCapacity: UInt64 = 16 * 1_024 * 1_024

        // When
        dataCache.memoryCapacity = memoryCapacity
        dataCache.diskCapacity = diskCapacity

        // Then
        #expect(dataCache.memoryCapacity == memoryCapacity)
        #expect(dataCache.diskCapacity == diskCapacity)
    }

    @Test
    func cache_whenSetCachedData() throws {
        let testState = TestState()
        defer { _ = testState }
        // Given
        let dataCache = testState.dataCache

        let key1 = "https://google.com"
        let key2 = "https://apple.com"

        let data1 = Data.randomData(length: 1_024)
        let data2 = Data.randomData(length: 8 * 1_024)

        // When
        for (key, data) in [(key1, data1), (key2, data2)] {
            dataCache.setCachedData(
                CachedData(
                    response: mockResponse(url: key),
                    policy: .all,
                    data: data
                ),
                forKey: key
            )
        }

        let cachedMemory1 = dataCache.getCachedData(forKey: key1, policy: .memory)
        let cachedDisk1 = dataCache.getCachedData(forKey: key1, policy: .disk)

        let cachedMemory2 = dataCache.getCachedData(forKey: key2, policy: .memory)
        let cachedDisk2 = dataCache.getCachedData(forKey: key2, policy: .disk)

        // Then
        #expect(cachedMemory1?.data == data1)
        #expect(cachedDisk1?.data == data1)

        #expect(cachedMemory2?.data == data2)
        #expect(cachedDisk2?.data == data2)
    }

    @Test
    func cache_whenLowMemory() throws {
        let testState = TestState()
        // Given
        let dataCache = testState.dataCache

        dataCache.memoryCapacity = 1_024

        let key1 = "https://google.com"
        let key2 = "https://apple.com"

        let cachedData1 = mockCachedData(
            url: key1,
            length: 1_024 - 256,
            policy: .memory
        )

        let cachedData2 = mockCachedData(
            url: key2,
            length: 512,
            policy: .memory
        )

        // When
        dataCache.setCachedData(cachedData1, forKey: key1)
        dataCache.setCachedData(cachedData2, forKey: key2)

        let cachedMemory1 = dataCache.getCachedData(forKey: key1, policy: .memory)
        let cachedMemory2 = dataCache.getCachedData(forKey: key2, policy: .memory)

        // Then
        #expect(cachedMemory1 == nil)

        #expect(cachedMemory2?.data == cachedData2.data)
    }

    @Test
    func cache_whenLowDisk() throws {
        let testState = TestState()
        defer { _ = testState }
        // Given
        let dataCache = testState.dataCache

        dataCache.diskCapacity = 1_024

        let key1 = "https://google.com"
        let key2 = "https://apple.com"

        let cachedData1 = mockCachedData(
            url: key1,
            length: 1_024 - 256,
            policy: .disk
        )

        let cachedData2 = mockCachedData(
            url: key2,
            length: 512,
            policy: .disk
        )

        // When
        dataCache.setCachedData(cachedData1, forKey: key1)
        dataCache.setCachedData(cachedData2, forKey: key2)

        let cachedDisk1 = dataCache.getCachedData(forKey: key1, policy: .disk)
        let cachedDisk2 = dataCache.getCachedData(forKey: key2, policy: .disk)

        // Then
        #expect(cachedDisk1 == nil)

        #expect(cachedDisk2?.data == cachedData2.data)
    }

    @Test
    func cache_whenRemoveKey() throws {
        let testState = TestState()
        defer { _ = testState }

        // Given
        let dataCache = testState.dataCache

        let key1 = "https://google.com"
        let key2 = "https://apple.com"

        let cachedData1 = mockCachedData(
            url: key1,
            length: 1_024 - 256
        )

        let cachedData2 = mockCachedData(
            url: key2,
            length: 512
        )

        // When
        dataCache.setCachedData(cachedData1, forKey: key1)
        dataCache.setCachedData(cachedData2, forKey: key2)

        let memoryCached1 = dataCache.getCachedData(forKey: key1, policy: .memory)
        let diskCached1 = dataCache.getCachedData(forKey: key1, policy: .disk)
        let diskCached1Data = diskCached1?.data

        dataCache.remove(forKey: key1)

        let memoryCached2 = dataCache.getCachedData(forKey: key2, policy: .memory)
        let diskCached2 = dataCache.getCachedData(forKey: key2, policy: .disk)

        let memoryCached1_v2 = dataCache.getCachedData(forKey: key1, policy: .memory)
        let diskCached1_v2 = dataCache.getCachedData(forKey: key1, policy: .disk)

        // Then
        #expect(memoryCached1?.data == cachedData1.data)
        #expect(diskCached1Data == cachedData1.data)

        #expect(memoryCached2?.data == cachedData2.data)
        #expect(diskCached2?.data == cachedData2.data)

        #expect(memoryCached1_v2 == nil)
        #expect(diskCached1_v2 == nil)
    }

    @Test
    func cache_whenRemoveSince() throws {
        let testState = TestState()
        // Given
        let dataCache = testState.dataCache

        let cachedDatas = (0 ..< 3) .map {
            mockCachedData(
                url: "https://google.com/\($0)",
                length: 1_024
            )
        }

        // When
        for cacheData in cachedDatas {
            dataCache.setCachedData(cacheData, forKey: cacheData.cachedResponse.response.url)
        }

        dataCache.removeAll(since: cachedDatas[1].cachedResponse.date)

        let storedDatas = [0, 1, 2].map {
            dataCache.getCachedData(forKey: "https://google.com/\($0)", policy: .all)
        }

        // Then
        #expect(storedDatas[0] == nil)
        #expect(storedDatas[1] == nil)
        #expect(storedDatas[2]?.data == cachedDatas[2].data)
    }

    @Test
    func cache_whenRemoveAll() throws {
        let testState = TestState()
        // Given
        let dataCache = testState.dataCache

        let cachedDatas = (0 ..< 3) .map {
            mockCachedData(
                url: "https://google.com/\($0)",
                length: 1_024
            )
        }

        // When
        for cacheData in cachedDatas {
            dataCache.setCachedData(cacheData, forKey: cacheData.cachedResponse.response.url)
        }

        dataCache.removeAll()

        let storedDatas = [0, 1, 2].map {
            dataCache.getCachedData(forKey: "https://google.com/\($0)", policy: .all)
        }

        // Then
        #expect(storedDatas[0] == nil)
        #expect(storedDatas[1] == nil)
        #expect(storedDatas[2] == nil)
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
        let dateFormatter = DateFormatter()

        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        dateFormatter.timeZone = TimeZone(identifier: "GMT")

        return ResponseHead(
            url: URL(string: url),
            status: .init(code: 200, reason: "Ok"),
            version: .init(minor: 1, major: 2),
            headers: HTTPHeaders([
                ("Expires", dateFormatter.string(from: expirationDate)),
                ("ETag", "\(UUID())")
            ]),
            isKeepAlive: false
        )
    }

    func mockCachedData(
        url: String,
        length: Int,
        policy: DataCache.Policy.Set = .all,
        expiresAt expirationDate: Date = .distantFuture
    ) -> CachedData {
        CachedData(
            response: mockResponse(url: url, expiresAt: expirationDate),
            policy: policy,
            data: Data.randomData(length: length)
        )
    }
}
