/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

@Suite(.serialized)
struct CachePropertiesTests {

    func resetCapacity() {
        DataCache.shared.memoryCapacity = .zero
        DataCache.shared.diskCapacity = .zero
    }

    @Test
    func cache_whenCacheSharedWithoutCapacity() async throws {
        defer { resetCapacity() }
        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cache()
        })

        // Then
        #expect(resolved.dataCache == DataCache.shared)
    }

    @Test
    func cache_whenCacheSharedWithCapacity() async throws {
        defer { resetCapacity() }
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
        #expect(resolved.dataCache == DataCache.shared)

        #expect(resolved.dataCache.memoryCapacity == memoryCapacity)
        #expect(resolved.dataCache.diskCapacity == diskCapacity)

        #expect(DataCache.shared.memoryCapacity == memoryCapacity)
        #expect(DataCache.shared.diskCapacity == diskCapacity)
    }

    @Test
    func cache_whenCacheSuiteNameWithoutCapacity() async throws {
        defer { resetCapacity() }
        // Given
        let suiteName = "hello_world"

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cache(suiteName: suiteName)
        })

        // Then
        #expect(resolved.dataCache == DataCache(suiteName: suiteName))
    }

    @Test
    func cache_whenCacheSuiteNameWithCapacity() async throws {
        defer { resetCapacity() }
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
        #expect(resolved.dataCache == dataCache)

        #expect(resolved.dataCache.memoryCapacity == memoryCapacity)
        #expect(resolved.dataCache.diskCapacity == diskCapacity)

        #expect(dataCache.memoryCapacity == memoryCapacity)
        #expect(dataCache.diskCapacity == diskCapacity)
    }

    @Test
    func cache_whenCacheURLWithoutCapacity() async throws {
        defer { resetCapacity() }
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
        #expect(resolved.dataCache == DataCache(url: url))
    }

    @Test
    func cache_whenCacheURLWithCapacity() async throws {
        defer { resetCapacity() }
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
        #expect(resolved.dataCache == dataCache)

        #expect(resolved.dataCache.memoryCapacity == memoryCapacity)
        #expect(resolved.dataCache.diskCapacity == diskCapacity)

        #expect(dataCache.memoryCapacity == memoryCapacity)
        #expect(dataCache.diskCapacity == diskCapacity)
    }

    @Test
    func cache_whenMemoryCachePolicy() async throws {
        defer { resetCapacity() }
        // Given
        let policy = DataCache.Policy.Set.memory

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cachePolicy(policy)
        })

        // Then
        #expect(resolved.requestConfiguration.cachePolicy == policy)
    }

    @Test
    func cache_whenDiskCachePolicy() async throws {
        defer { resetCapacity() }
        // Given
        let policy = DataCache.Policy.Set.disk

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cachePolicy(policy)
        })

        // Then
        #expect(resolved.requestConfiguration.cachePolicy == policy)
    }

    @Test
    func cache_whenAllCachePolicy() async throws {
        defer { resetCapacity() }
        // Given
        let policy = DataCache.Policy.Set.all

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cachePolicy(policy)
        })

        // Then
        #expect(resolved.requestConfiguration.cachePolicy == policy)
    }

    @Test
    func cache_whenIgnoreCachedDataStrategy() async throws {
        defer { resetCapacity() }
        // Given
        let cacheStrategy = CacheStrategy.ignoreCachedData

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cacheStrategy(cacheStrategy)
        })

        // Then
        #expect(resolved.requestConfiguration.cacheStrategy == cacheStrategy)
    }

    @Test
    func cache_whenReloadAndValidateCachedDataStrategy() async throws {
        defer { resetCapacity() }
        // Given
        let cacheStrategy = CacheStrategy.reloadAndValidateCachedData

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cacheStrategy(cacheStrategy)
        })

        // Then
        #expect(resolved.requestConfiguration.cacheStrategy == cacheStrategy)
    }

    @Test
    func cache_whenReturnCachedDataElseLoadStrategy() async throws {
        defer { resetCapacity() }
        // Given
        let cacheStrategy = CacheStrategy.returnCachedDataElseLoad

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cacheStrategy(cacheStrategy)
        })

        // Then
        #expect(resolved.requestConfiguration.cacheStrategy == cacheStrategy)
    }

    @Test
    func cache_whenUseCachedDataOnlyStrategy() async throws {
        defer { resetCapacity() }
        // Given
        let cacheStrategy = CacheStrategy.useCachedDataOnly

        // When
        let resolved = try await resolve(TestProperty {
            EmptyProperty()
                .cacheStrategy(cacheStrategy)
        })

        // Then
        #expect(resolved.requestConfiguration.cacheStrategy == cacheStrategy)
    }
}
