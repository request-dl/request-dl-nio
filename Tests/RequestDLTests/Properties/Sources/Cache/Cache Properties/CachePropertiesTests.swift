/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class CachePropertiesTests: XCTestCase {

    func testCache_whenCacheSharedWithoutCapacity() async throws {
        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cache()
        })

        // Then
        XCTAssertEqual(resolved.dataCache, DataCache.shared)
    }

    func testCache_whenCacheSharedWithCapacity() async throws {
        // Given
        let memoryCapacity: UInt64 = 128 * 1_024 * 1_024
        let diskCapacity: UInt64 = 1_024 * 1_024 * 1_024

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cache(
                    memoryCapacity: memoryCapacity,
                    diskCapacity: diskCapacity
                )
        })

        // Then
        XCTAssertEqual(resolved.dataCache, DataCache.shared)

        XCTAssertEqual(resolved.dataCache.memoryCapacity, memoryCapacity)
        XCTAssertEqual(resolved.dataCache.diskCapacity, diskCapacity)

        XCTAssertEqual(DataCache.shared.memoryCapacity, memoryCapacity)
        XCTAssertEqual(DataCache.shared.diskCapacity, diskCapacity)
    }

    func testCache_whenCacheSuiteNameWithoutCapacity() async throws {
        // Given
        let suiteName = "hello_world"

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cache(suiteName: suiteName)
        })

        // Then
        XCTAssertEqual(resolved.dataCache, DataCache(suiteName: suiteName))
    }

    func testCache_whenCacheSuiteNameWithCapacity() async throws {
        // Given
        let suiteName = "hello_world"
        let memoryCapacity: UInt64 = 128 * 1_024 * 1_024
        let diskCapacity: UInt64 = 1_024 * 1_024 * 1_024

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cache(
                    memoryCapacity: memoryCapacity,
                    diskCapacity: diskCapacity,
                    suiteName: suiteName
                )
        })

        let dataCache = DataCache(suiteName: suiteName)

        // Then
        XCTAssertEqual(resolved.dataCache, dataCache)

        XCTAssertEqual(resolved.dataCache.memoryCapacity, memoryCapacity)
        XCTAssertEqual(resolved.dataCache.diskCapacity, diskCapacity)

        XCTAssertEqual(dataCache.memoryCapacity, memoryCapacity)
        XCTAssertEqual(dataCache.diskCapacity, diskCapacity)
    }

    func testCache_whenCacheURLWithoutCapacity() async throws {
        // Given
        let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("cache_system")

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cache(url: url)
        })

        // Then
        XCTAssertEqual(resolved.dataCache, DataCache(url: url))
    }

    func testCache_whenCacheURLWithCapacity() async throws {
        // Given
        let url = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0].appendingPathComponent("cache_system")

        let memoryCapacity: UInt64 = 128 * 1_024 * 1_024
        let diskCapacity: UInt64 = 1_024 * 1_024 * 1_024

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cache(
                    memoryCapacity: memoryCapacity,
                    diskCapacity: diskCapacity,
                    url: url
                )
        })

        let dataCache = DataCache(url: url)

        // Then
        XCTAssertEqual(resolved.dataCache, dataCache)

        XCTAssertEqual(resolved.dataCache.memoryCapacity, memoryCapacity)
        XCTAssertEqual(resolved.dataCache.diskCapacity, diskCapacity)

        XCTAssertEqual(dataCache.memoryCapacity, memoryCapacity)
        XCTAssertEqual(dataCache.diskCapacity, diskCapacity)
    }

    func testCache_whenMemoryCachePolicy() async throws {
        // Given
        let policy = DataCache.Policy.Set.memory

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cachePolicy(policy)
        })

        // Then
        XCTAssertEqual(resolved.request.cachePolicy, policy)
    }

    func testCache_whenDiskCachePolicy() async throws {
        // Given
        let policy = DataCache.Policy.Set.disk

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cachePolicy(policy)
        })

        // Then
        XCTAssertEqual(resolved.request.cachePolicy, policy)
    }

    func testCache_whenAllCachePolicy() async throws {
        // Given
        let policy = DataCache.Policy.Set.all

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cachePolicy(policy)
        })

        // Then
        XCTAssertEqual(resolved.request.cachePolicy, policy)
    }

    func testCache_whenIgnoreCachedDataStrategy() async throws {
        // Given
        let cacheStrategy = CacheStrategy.ignoreCachedData

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cacheStrategy(cacheStrategy)
        })

        // Then
        XCTAssertEqual(resolved.request.cacheStrategy, cacheStrategy)
    }

    func testCache_whenReloadAndValidateCachedDataStrategy() async throws {
        // Given
        let cacheStrategy = CacheStrategy.reloadAndValidateCachedData

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cacheStrategy(cacheStrategy)
        })

        // Then
        XCTAssertEqual(resolved.request.cacheStrategy, cacheStrategy)
    }

    func testCache_whenReturnCachedDataElseLoadStrategy() async throws {
        // Given
        let cacheStrategy = CacheStrategy.returnCachedDataElseLoad

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cacheStrategy(cacheStrategy)
        })

        // Then
        XCTAssertEqual(resolved.request.cacheStrategy, cacheStrategy)
    }

    func testCache_whenUseCachedDataOnlyStrategy() async throws {
        // Given
        let cacheStrategy = CacheStrategy.useCachedDataOnly

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cacheStrategy(cacheStrategy)
        })

        // Then
        XCTAssertEqual(resolved.request.cacheStrategy, cacheStrategy)
    }
}
