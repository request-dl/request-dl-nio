//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@testable import RequestDL

#if canImport(UIKit) || canImport(AppKit)
struct RDLImageLoaderTests {

    @Test
    func decodesValidImageData() async throws {
        // Given
        let loader = RDLImageLoader()
        let task = StubImageTask { .init(head: .stub, payload: .onePixelPNG) }

        // When
        let image = try await loader.load(id: "valid", task: task)

        // Then
        #expect(image.size.width > 0)
        #expect(image.size.height > 0)
    }

    @Test
    func throwsOnInvalidImageData() async throws {
        // Given
        let loader = RDLImageLoader()
        let task = StubImageTask { .init(head: .stub, payload: Data("not an image".utf8)) }

        // When/Then
        do {
            _ = try await loader.load(id: "invalid", task: task)
            Issue.record("Expected RDLImageDecodingError")
        } catch is RDLImageDecodingError {
            // expected
        }
    }

    @Test
    func dedupesConcurrentLoadsForTheSameID() async throws {
        // Given
        let counter = Counter()

        let task = StubImageTask {
            await counter.increment()
            try await Task.sleep(nanoseconds: 50_000_000)
            return .init(head: .stub, payload: .onePixelPNG)
        }

        let loader = RDLImageLoader()

        // When
        async let first = loader.load(id: "shared", task: task)
        async let second = loader.load(id: "shared", task: task)

        let firstImage = try await first
        let secondImage = try await second

        // Then
        #expect(firstImage.size == secondImage.size)
        #expect(await counter.value == 1)
    }

    @Test
    func defaultDataCache_isSeparateFromDataCacheShared() async throws {
        // Given/When
        let loader = RDLImageLoader()

        // Then: a default-constructed loader gets its own cache directory, so image bytes
        // don't compete for space with, or get evicted by, unrelated HTTP responses the host
        // app caches through `DataCache.shared`.
        #expect(await loader.dataCache != DataCache.shared)
    }

    @Test
    func defaultDataCache_hasDiskCachingEnabled() async throws {
        // Given/When
        let loader = RDLImageLoader()

        // Then: disk caching is on by default — a zero capacity would silently make every
        // cache write a no-op regardless of the policy `load(url:)` applies.
        #expect(await loader.dataCache.diskCapacity > .zero)
    }

    @Test
    func twoDefaultConstructedLoaders_shareTheSameCacheDirectory() async throws {
        // Given/When
        let first = RDLImageLoader()
        let second = RDLImageLoader()

        // Then: both resolve to the same suite name, so they end up backed by the same
        // directory (and, in turn, the same underlying disk storage) rather than each silently
        // fragmenting the cache.
        #expect(await first.dataCache == second.dataCache)
    }

    @Test
    func init_whenGivenACustomDataCache_usesItInsteadOfTheDefault() async throws {
        // Given
        let customDataCache = DataCache(diskCapacity: 1_024, suiteName: "custom-rdlimage-loader-test")

        // When
        let loader = RDLImageLoader(dataCache: customDataCache)

        // Then
        #expect(await loader.dataCache == customDataCache)
        #expect(await loader.dataCache != RDLImageLoader().dataCache)
    }

    @Test
    func doesNotDedupeAcrossDifferentIDs() async throws {
        // Given
        let counter = Counter()

        let task = StubImageTask {
            await counter.increment()
            return .init(head: .stub, payload: .onePixelPNG)
        }

        let loader = RDLImageLoader()

        // When
        _ = try await loader.load(id: "first", task: task)
        _ = try await loader.load(id: "second", task: task)

        // Then
        #expect(await counter.value == 2)
    }
}

// MARK: - Test helpers

private struct StubImageTask: RequestTask {

    let onResult: @Sendable () async throws -> TaskResult<Data>

    func result() async throws -> TaskResult<Data> {
        try await onResult()
    }
}

private actor Counter {

    private(set) var value = 0

    func increment() {
        value += 1
    }
}

extension ResponseHead {

    fileprivate static let stub = ResponseHead(
        url: nil,
        status: .init(code: 200, reason: "OK"),
        version: .init(minor: 1, major: 1),
        headers: HTTPHeaders(),
        isKeepAlive: false
    )
}

extension Data {

    /// A minimal, valid 1x1 transparent PNG, used to exercise real image decoding without
    /// bundling a resource file.
    fileprivate static let onePixelPNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
    )!
}
#endif
