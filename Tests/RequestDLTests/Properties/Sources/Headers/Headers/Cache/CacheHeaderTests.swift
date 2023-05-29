/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class CacheHeaderTests: XCTestCase {

    func testDefaultValues() async throws {
        let cache = CacheHeader()

        XCTAssertTrue(cache.isCached)
        XCTAssertTrue(cache.isStored)
        XCTAssertTrue(cache.isTransformed)
        XCTAssertFalse(cache.isOnlyIfCached)
        XCTAssertNil(cache.isPublic)
        XCTAssertNil(cache.maxAge)
        XCTAssertNil(cache.sharedMaxAge)
        XCTAssertNil(cache.maxStale)
        XCTAssertNil(cache.staleWhileRevalidate)
        XCTAssertNil(cache.staleIfError)
        XCTAssertFalse(cache.needsRevalidate)
        XCTAssertFalse(cache.needsProxyRevalidate)
        XCTAssertFalse(cache.isImmutable)
    }

    func testInitializationWithPolicy() async throws {
        // Given
        let cache = CacheHeader()

        // When
        let resolved = try await resolve(TestProperty(cache))

        // Then
        XCTAssertTrue(cache.isCached)
        XCTAssertTrue(cache.isStored)
        XCTAssertTrue(cache.isTransformed)
        XCTAssertFalse(cache.isOnlyIfCached)
        XCTAssertNil(cache.isPublic)
        XCTAssertNil(cache.maxAge)
        XCTAssertNil(cache.sharedMaxAge)
        XCTAssertNil(cache.maxStale)
        XCTAssertNil(cache.staleWhileRevalidate)
        XCTAssertNil(cache.staleIfError)
        XCTAssertFalse(cache.needsRevalidate)
        XCTAssertFalse(cache.needsProxyRevalidate)
        XCTAssertFalse(cache.isImmutable)

        XCTAssertTrue(resolved.request.headers.isEmpty)
    }

    func testModifiedCacheWithAllProperties() async throws {
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
        XCTAssertFalse(modifiedCache.isCached)
        XCTAssertFalse(modifiedCache.isStored)
        XCTAssertFalse(modifiedCache.isTransformed)
        XCTAssertTrue(modifiedCache.isOnlyIfCached)
        XCTAssertEqual(modifiedCache.isPublic, false)
        XCTAssertEqual(modifiedCache.maxAge, 1_000)
        XCTAssertEqual(modifiedCache.sharedMaxAge, 16_000)
        XCTAssertEqual(modifiedCache.maxStale, 300)
        XCTAssertEqual(modifiedCache.staleWhileRevalidate, 120)
        XCTAssertEqual(modifiedCache.staleIfError, 86400)
        XCTAssertTrue(modifiedCache.needsRevalidate)
        XCTAssertTrue(modifiedCache.needsProxyRevalidate)
        XCTAssertTrue(modifiedCache.isImmutable)

        XCTAssertEqual(
            resolved.request.headers["Cache-Control"],
            [
                """
                no-cache, no-store, no-transform, only-if-cached, private, max-age=1000, \
                s-maxage=16000, max-stale=300, stale-while-revalidate=120, stale-if-error=86400, \
                must-revalidate, proxy-revalidate, immutable
                """
            ]
        )
    }

    func testPublicCache() async throws {
        // Given
        let cache = CacheHeader()
            .public(true)

        // When
        let resolved = try await resolve(TestProperty(cache))

        // Then
        XCTAssertEqual(resolved.request.headers["Cache-Control"], ["public"])
    }

    func testNeverBody() async throws {
        // Given
        let property = CacheHeader()

        // Then
        try await assertNever(property.body)
    }
}
