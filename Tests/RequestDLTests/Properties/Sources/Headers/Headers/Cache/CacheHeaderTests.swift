/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

struct CacheHeaderTests {

    @Test
    func defaultValues() async throws {
        let cache = CacheHeader()

        #expect(cache.isCached)
        #expect(cache.isStored)
        #expect(cache.isTransformed)
        #expect(!cache.isOnlyIfCached)
        #expect(cache.isPublic == nil)
        #expect(cache.maxAge == nil)
        #expect(cache.sharedMaxAge == nil)
        #expect(cache.maxStale == nil)
        #expect(cache.staleWhileRevalidate == nil)
        #expect(cache.staleIfError == nil)
        #expect(!cache.needsRevalidate)
        #expect(!cache.needsProxyRevalidate)
        #expect(!cache.isImmutable)
    }

    @Test
    func initializationWithPolicy() async throws {
        // Given
        let cache = CacheHeader()

        // When
        let resolved = try await resolve(TestProperty(cache))

        // Then
        #expect(cache.isCached)
        #expect(cache.isStored)
        #expect(cache.isTransformed)
        #expect(!cache.isOnlyIfCached)
        #expect(cache.isPublic == nil)
        #expect(cache.maxAge == nil)
        #expect(cache.sharedMaxAge == nil)
        #expect(cache.maxStale == nil)
        #expect(cache.staleWhileRevalidate == nil)
        #expect(cache.staleIfError == nil)
        #expect(!cache.needsRevalidate)
        #expect(!cache.needsProxyRevalidate)
        #expect(!cache.isImmutable)

        #expect(resolved.request.headers.isEmpty)
    }

    @Test
    func modifiedCacheWithAllProperties() async throws {
        // Given
        let cache = CacheHeader()

        let modifiedCache = cache
            .cached(false)
            .stored(false)
            .transformed(false)
            .onlyIfCached(true)
            .public(false) // nil
            .maxAge(1_000)
            .sharedMaxAge(16_000)
            .maxStale(300)
            .staleWhileRevalidate(120)
            .staleIfError(86400)
            .mustRevalidate()
            .proxyRevalidate()
            .immutable()

        // When
        let resolved = try await resolve(TestProperty(modifiedCache))

        // Then
        #expect(!modifiedCache.isCached)
        #expect(!modifiedCache.isStored)
        #expect(!modifiedCache.isTransformed)
        #expect(modifiedCache.isOnlyIfCached)
        #expect(modifiedCache.isPublic == false)
        #expect(modifiedCache.maxAge == 1_000)
        #expect(modifiedCache.sharedMaxAge == 16_000)
        #expect(modifiedCache.maxStale == 300)
        #expect(modifiedCache.staleWhileRevalidate == 120)
        #expect(modifiedCache.staleIfError == 86400)
        #expect(modifiedCache.needsRevalidate)
        #expect(modifiedCache.needsProxyRevalidate)
        #expect(modifiedCache.isImmutable)

        #expect(
            resolved.request.headers["Cache-Control"] == [
                """
                no-cache,no-store,no-transform,only-if-cached,private,max-age=1000,\
                s-maxage=16000,max-stale=300,stale-while-revalidate=120,stale-if-error=86400,\
                must-revalidate,proxy-revalidate,immutable
                """
            ]
        )
    }

    @Test
    func publicCache() async throws {
        // Given
        let cache = CacheHeader()
            .public(true)

        // When
        let resolved = try await resolve(TestProperty(cache))

        // Then
        #expect(resolved.request.headers["Cache-Control"] == ["public"])
    }

    @Test
    func neverBody() async throws {
        // Given
        let property = CacheHeader()

        // Then
        try await assertNever(property.body)
    }
}
