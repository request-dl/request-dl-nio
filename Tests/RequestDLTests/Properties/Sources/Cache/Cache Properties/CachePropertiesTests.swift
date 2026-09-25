//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

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
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cache()
            }
        )

        // Then
        #expect(resolved.dataCache == DataCache.shared)
    }

    /// Every request's resolve builds its cache configuration, and a `DataCache` is shared per
    /// directory — `.main` is the very same storage as `DataCache.shared`. A request that doesn't
    /// pass `encryptionKey` must therefore leave whatever key that cache already has alone;
    /// otherwise any ordinary request silently clears a key set through
    /// `DataCache.encryptionKey`, and every disk-tier write after it lands in plaintext.
    @Test
    func cache_whenEncryptionKeyNotSpecified_preservesTheCachesExistingKey() async throws {
        // Given
        let suiteName = "encryption-key-" + String.randomString(length: 16)
        let encryptionKey = DataCache.EncryptionKey(Data(repeating: 0x2A, count: 32))
        DataCache(suiteName: suiteName).encryptionKey = encryptionKey

        // When
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cache(suiteName: suiteName)
            }
        )

        // Then
        #expect(resolved.dataCache.encryptionKey == encryptionKey)
        #expect(DataCache(suiteName: suiteName).encryptionKey == encryptionKey)
    }

    @Test
    func cache_whenEncryptionKeySpecified_replacesTheCachesExistingKey() async throws {
        // Given
        let suiteName = "encryption-key-" + String.randomString(length: 16)
        let previousKey = DataCache.EncryptionKey(Data(repeating: 0x2A, count: 32))
        let encryptionKey = DataCache.EncryptionKey(Data(repeating: 0x2B, count: 32))
        DataCache(suiteName: suiteName).encryptionKey = previousKey

        // When
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cache(suiteName: suiteName, encryptionKey: encryptionKey)
            }
        )

        // Then
        #expect(resolved.dataCache.encryptionKey == encryptionKey)
    }

    @Test
    func cache_whenCacheSharedWithCapacity() async throws {
        defer { resetCapacity() }
        // Given
        let memoryCapacity: Int64 = 128 * 1_024 * 1_024
        let diskCapacity: Int64 = 1_024 * 1_024 * 1_024

        // When
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cache(
                        memoryCapacity: memoryCapacity,
                        diskCapacity: diskCapacity
                    )
            }
        )

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
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cache(suiteName: suiteName)
            }
        )

        // Then
        #expect(resolved.dataCache == DataCache(suiteName: suiteName))
    }

    @Test
    func cache_whenCacheSuiteNameWithCapacity() async throws {
        defer { resetCapacity() }
        // Given
        let suiteName = "hello_world"
        let memoryCapacity: Int64 = 128 * 1_024 * 1_024
        let diskCapacity: Int64 = 1_024 * 1_024 * 1_024

        // When
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cache(
                        memoryCapacity: memoryCapacity,
                        diskCapacity: diskCapacity,
                        suiteName: suiteName
                    )
            }
        )

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
        // Any distinct directory works: this only checks that a custom `url` is honored, not
        // the real application support directory. `FileManager` is not part of
        // `FoundationEssentials`; the system temporary directory is the portable stand-in
        // already used elsewhere in the test suite.
        let url = temporaryDirectoryURL.appendingPathComponent("cache_system")

        // When
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cache(url: url)
            }
        )

        // Then
        #expect(resolved.dataCache == DataCache(url: url))
    }

    @Test
    func cache_whenCacheURLWithCapacity() async throws {
        defer { resetCapacity() }
        // Given
        // Any distinct directory works: this only checks that a custom `url` is honored, not
        // the real application support directory. `FileManager` is not part of
        // `FoundationEssentials`; the system temporary directory is the portable stand-in
        // already used elsewhere in the test suite.
        let url = temporaryDirectoryURL.appendingPathComponent("cache_system")

        let memoryCapacity: Int64 = 128 * 1_024 * 1_024
        let diskCapacity: Int64 = 1_024 * 1_024 * 1_024

        // When
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cache(
                        memoryCapacity: memoryCapacity,
                        diskCapacity: diskCapacity,
                        url: url
                    )
            }
        )

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
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cachePolicy(policy)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.cachePolicy == policy)
    }

    @Test
    func cache_whenDiskCachePolicy() async throws {
        defer { resetCapacity() }
        // Given
        let policy = DataCache.Policy.Set.disk

        // When
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cachePolicy(policy)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.cachePolicy == policy)
    }

    @Test
    func cache_whenAllCachePolicy() async throws {
        defer { resetCapacity() }
        // Given
        let policy = DataCache.Policy.Set.all

        // When
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cachePolicy(policy)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.cachePolicy == policy)
    }

    @Test
    func cache_whenIgnoreCachedDataStrategy() async throws {
        defer { resetCapacity() }
        // Given
        let cacheStrategy = CacheStrategy.ignoreCachedData

        // When
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cacheStrategy(cacheStrategy)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.cacheStrategy == cacheStrategy)
    }

    @Test
    func cache_whenReloadAndValidateCachedDataStrategy() async throws {
        defer { resetCapacity() }
        // Given
        let cacheStrategy = CacheStrategy.reloadAndValidateCachedData

        // When
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cacheStrategy(cacheStrategy)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.cacheStrategy == cacheStrategy)
    }

    @Test
    func cache_whenReturnCachedDataElseLoadStrategy() async throws {
        defer { resetCapacity() }
        // Given
        let cacheStrategy = CacheStrategy.returnCachedDataElseLoad

        // When
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cacheStrategy(cacheStrategy)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.cacheStrategy == cacheStrategy)
    }

    @Test
    func cache_whenUseCachedDataOnlyStrategy() async throws {
        defer { resetCapacity() }
        // Given
        let cacheStrategy = CacheStrategy.useCachedDataOnly

        // When
        let resolved = try await resolve(
            TestProperty {
                EmptyProperty()
                    .cacheStrategy(cacheStrategy)
            }
        )

        // Then
        #expect(resolved.requestConfiguration.cacheStrategy == cacheStrategy)
    }
}
