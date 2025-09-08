/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class DataCacheTests: XCTestCase {

    let memoryCapacity: UInt64 = 8 * 1_024 * 1_024
    let diskCapacity: UInt64 = 64 * 1_024 * 1_024

    var dataCache: DataCache?

    override func setUp() async throws {
        try await super.setUp()
        dataCache = .init(
            memoryCapacity: 8 * 1_024 * 1_024,
            diskCapacity: 64 * 1_024 * 1_024
        )
    }

    override func tearDown() async throws {
        try await super.tearDown()
        dataCache?.removeAll()
        dataCache = nil

        DataCache.shared.memoryCapacity = .zero
        DataCache.shared.diskCapacity = .zero
    }

    func testCache_whenInit_shouldCapacityBeKnown() throws {
        // Given
        let dataCache = try XCTUnwrap(dataCache)

        // Then
        XCTAssertEqual(dataCache.memoryCapacity, memoryCapacity)
        XCTAssertEqual(dataCache.diskCapacity, diskCapacity)
    }

    func testCache_whenInitWithLowerCapacityPreviousSpecified_shouldBeMax() {
        // Given
        let memoryCapacity: UInt64 = 4 * 1_024 * 1_024
        let diskCapacity: UInt64 = 16 * 1_024 * 1_024

        // When
        let dataCache = DataCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity
        )

        // Then
        XCTAssertEqual(dataCache.memoryCapacity, self.memoryCapacity)
        XCTAssertEqual(dataCache.diskCapacity, self.diskCapacity)
    }

    func testCache_whenSetCapacityDirectly_shouldBeValid() throws {
        // Given
        let dataCache = try XCTUnwrap(dataCache)

        let memoryCapacity: UInt64 = 4 * 1_024 * 1_024
        let diskCapacity: UInt64 = 16 * 1_024 * 1_024

        // When
        dataCache.memoryCapacity = memoryCapacity
        dataCache.diskCapacity = diskCapacity

        // Then
        XCTAssertEqual(dataCache.memoryCapacity, memoryCapacity)
        XCTAssertEqual(dataCache.diskCapacity, diskCapacity)
    }

    func testCache_whenSetCachedData() throws {
        // Given
        let dataCache = try XCTUnwrap(dataCache)

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
        XCTAssertEqual(cachedMemory1?.data, data1)
        XCTAssertEqual(cachedDisk1?.data, data1)

        XCTAssertEqual(cachedMemory2?.data, data2)
        XCTAssertEqual(cachedDisk2?.data, data2)
    }

    func testCache_whenLowMemory() throws {
        // Given
        let dataCache = try XCTUnwrap(dataCache)

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
        XCTAssertNil(cachedMemory1)

        XCTAssertEqual(cachedMemory2?.data, cachedData2.data)
    }

    func testCache_whenLowDisk() throws {
        // Given
        let dataCache = try XCTUnwrap(dataCache)

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
        XCTAssertNil(cachedDisk1)

        XCTAssertEqual(cachedDisk2?.data, cachedData2.data)
    }

    func testCache_whenRemoveKey() throws {
        // Given
        let dataCache = try XCTUnwrap(dataCache)

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
        XCTAssertEqual(memoryCached1?.data, cachedData1.data)
        XCTAssertEqual(diskCached1Data, cachedData1.data)

        XCTAssertEqual(memoryCached2?.data, cachedData2.data)
        XCTAssertEqual(diskCached2?.data, cachedData2.data)

        XCTAssertNil(memoryCached1_v2)
        XCTAssertNil(diskCached1_v2)
    }

    func testCache_whenRemoveSince() throws {
        // Given
        let dataCache = try XCTUnwrap(dataCache)

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
        XCTAssertNil(storedDatas[0])
        XCTAssertNil(storedDatas[1])
        XCTAssertEqual(storedDatas[2]?.data, cachedDatas[2].data)
    }

    func testCache_whenRemoveAll() throws {
        // Given
        let dataCache = try XCTUnwrap(dataCache)

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
        XCTAssertNil(storedDatas[0])
        XCTAssertNil(storedDatas[1])
        XCTAssertNil(storedDatas[2])
    }

    func testCache_whenInitWithSuiteName() {
        // Given
        let suiteName = "shared_other_lib"

        // When
        let dataCache = DataCache(suiteName: suiteName)

        let suiteURL = DataCache.temporaryURL(suiteName: suiteName)

        // Then
        XCTAssertEqual(dataCache, DataCache(url: suiteURL))
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
