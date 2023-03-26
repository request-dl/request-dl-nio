/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

final class HeadersCacheTests: XCTestCase {

    func testDefaultValues() {
        let cache = Headers.Cache()

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
        let policy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
        let memoryCapacity = 10_000_000
        let diskCapacity = 1_000_000_000

        // When
        let cache = Headers.Cache(
            policy,
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity
        )

        let (session, request) = try await resolve(TestProperty(cache))

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

        XCTAssertNil(request.allHTTPHeaderFields)
        XCTAssertEqual(session.configuration.requestCachePolicy, policy)
        XCTAssertEqual(session.configuration.urlCache?.memoryCapacity, memoryCapacity)
        XCTAssertEqual(session.configuration.urlCache?.diskCapacity, diskCapacity)
    }

    func testModifiedCacheWithAllProperties() async throws {
        // Given
        let policy = URLRequest.CachePolicy.reloadIgnoringLocalCacheData
        let cache = Headers.Cache(policy)

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
        let (session, request) = try await resolve(TestProperty(modifiedCache))

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

        XCTAssertEqual(session.configuration.requestCachePolicy, policy)

        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Cache-Control"),
            """
            no-cache, no-store, no-transform, only-if-cached, private, max-age=1000, \
            s-maxage=16000, max-stale=300, stale-while-revalidate=120, stale-if-error=86400, \
            must-revalidate, proxy-revalidate, immutable
            """
        )
    }

    func testPublicCache() async throws {
        // Given
        let cache = Headers.Cache()
            .public(true)

        // When
        let (_, request) = try await resolve(TestProperty(cache))

        // Then
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cache-Control"), "public")
    }

    func testNeverBody() async throws {
        // Given
        let property = Headers.Cache()

        // Then
        try await assertNever(property.body)
    }
}
