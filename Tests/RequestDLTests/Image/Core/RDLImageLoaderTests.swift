//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@_spi(Private) @testable import RequestDL
@testable import RequestDLTestSupport

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

        // Then: disk caching is on by default: a zero capacity would silently make every
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

    @Test
    func cancellingTheOnlyWaiter_cancelsTheRequest() async throws {
        // Given: a request that stays in flight until it is cancelled.
        let probe = RequestProbe()
        let task = StubImageTask {
            await probe.started()

            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
            } catch {
                await probe.cancelled()
                throw error
            }

            return .init(head: .stub, payload: .onePixelPNG)
        }

        let loader = RDLImageLoader()
        let load = Task { try await loader.load(id: "cancelled", task: task) }

        try await eventually { await probe.didStart }

        // When: the only caller waiting for it goes away, as a list row scrolled off screen does.
        load.cancel()

        // Then: the request is cancelled instead of running to the end for nobody, and the
        // caller does not get an image.
        try await eventually { await probe.wasCancelled }

        do {
            _ = try await load.value
            Issue.record("Expected the cancelled load to throw")
        } catch {
            // expected
        }
    }

    @Test
    func cancellingOneOfTwoWaiters_keepsTheRequestForTheOther() async throws {
        // Given: two callers sharing one request.
        let probe = RequestProbe()
        let task = StubImageTask {
            await probe.started()

            do {
                try await Task.sleep(nanoseconds: 200_000_000)
            } catch {
                await probe.cancelled()
                throw error
            }

            return .init(head: .stub, payload: .onePixelPNG)
        }

        let loader = RDLImageLoader()
        let first = Task { try await loader.load(id: "shared", task: task) }
        try await eventually { await probe.didStart }
        let second = Task { try await loader.load(id: "shared", task: task) }

        // Let the second caller register before the first one leaves.
        try await Task.sleep(nanoseconds: 50_000_000)

        // When: one of them is cancelled.
        first.cancel()

        // Then: the other still gets its image, and the request was never cancelled.
        let image = try await second.value
        #expect(image.size.width > 0)
        #expect(await probe.wasCancelled == false)
        #expect(await probe.startCount == 1)
    }

    /// The cancelled caller does not wait for the shared request: it stops at once, with a
    /// `CancellationError`, while the request goes on for the caller that is still waiting.
    @Test
    func cancellingOneOfTwoWaiters_returnsTheCancelledOneAtOnce_whileTheRequestStillRuns() async throws {
        // Given: two callers sharing one request that stays in flight until the gate is opened.
        let probe = RequestProbe()
        let gate = Gate()
        let task = StubImageTask {
            await probe.started()
            await gate.wait()

            return .init(head: .stub, payload: .onePixelPNG)
        }

        let loader = RDLImageLoader()
        let first = Task { try await loader.load(id: "shared", task: task) }
        try await eventually { await probe.didStart }
        let second = Task { try await loader.load(id: "shared", task: task) }
        try await eventually { await loader.waiterCountForTesting(id: "shared") == 2 }

        // When
        first.cancel()

        // Then: the first stops without the request having finished.
        let outcome = try await completing(within: 30) { () -> String in
            do {
                _ = try await first.value
                return "returned an image"
            } catch is CancellationError {
                return "cancelled"
            } catch {
                return "failed with \(error)"
            }
        }

        #expect(outcome == "cancelled")
        #expect(await gate.isOpen == false)
        #expect(await loader.waiterCountForTesting(id: "shared") == 1)

        // And the other still gets its image from the same request, which was never cancelled.
        await gate.open()

        let image = try await second.value
        #expect(image.size.width > 0)
        #expect(await probe.wasCancelled == false)
        #expect(await probe.startCount == 1)
    }

    @Test
    func cancellingEveryWaiterOfASharedRequest_cancelsIt() async throws {
        // Given: two callers sharing one request that would run for a long time.
        let probe = RequestProbe()
        let task = StubImageTask {
            await probe.started()

            do {
                try await Task.sleep(nanoseconds: 30_000_000_000)
            } catch {
                await probe.cancelled()
                throw error
            }

            return .init(head: .stub, payload: .onePixelPNG)
        }

        let loader = RDLImageLoader()
        let first = Task { try await loader.load(id: "shared", task: task) }
        try await eventually { await probe.didStart }
        let second = Task { try await loader.load(id: "shared", task: task) }
        try await eventually { await loader.waiterCountForTesting(id: "shared") == 2 }

        // When: the first leaves, and then the second does.
        first.cancel()
        try await eventually { await loader.waiterCountForTesting(id: "shared") == 1 }
        #expect(await probe.wasCancelled == false)

        second.cancel()

        // Then: the request is cancelled once nobody is left, and both callers stopped.
        try await eventually { await probe.wasCancelled }
        try await eventually { await loader.waiterCountForTesting(id: "shared") == 0 }

        for load in [first, second] {
            do {
                _ = try await load.value
                Issue.record("Expected the cancelled load to throw")
            } catch is CancellationError {
                // expected
            }
        }
    }

    /// A caller that arrives after the others left, but while the request still runs, joins it.
    @Test
    func aCallerThatJoinsAfterAnotherLeft_getsTheSameRequest() async throws {
        // Given
        let probe = RequestProbe()
        let gate = Gate()
        let task = StubImageTask {
            await probe.started()
            await gate.wait()

            return .init(head: .stub, payload: .onePixelPNG)
        }

        let loader = RDLImageLoader()
        let staying = Task { try await loader.load(id: "shared", task: task) }
        try await eventually { await probe.didStart }
        let leaving = Task { try await loader.load(id: "shared", task: task) }
        try await eventually { await loader.waiterCountForTesting(id: "shared") == 2 }
        leaving.cancel()
        try await eventually { await loader.waiterCountForTesting(id: "shared") == 1 }

        // When
        let joining = Task { try await loader.load(id: "shared", task: task) }
        try await eventually { await loader.waiterCountForTesting(id: "shared") == 2 }
        await gate.open()

        // Then: both get the image, from one request.
        #expect(try await staying.value.size.width > 0)
        #expect(try await joining.value.size.width > 0)
        #expect(await probe.startCount == 1)
    }

    @Test
    func loadingAgain_afterTheOnlyWaiterWasCancelled_startsANewRequest() async throws {
        // Given: a request that was cancelled together with its only waiter.
        let probe = RequestProbe()
        let task = StubImageTask {
            await probe.started()

            if await probe.startCount == 1 {
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                } catch {
                    await probe.cancelled()
                    throw error
                }
            }

            return .init(head: .stub, payload: .onePixelPNG)
        }

        let loader = RDLImageLoader()
        let abandoned = Task { try await loader.load(id: "again", task: task) }
        try await eventually { await probe.didStart }
        abandoned.cancel()
        try await eventually { await probe.wasCancelled }

        // When: the same image is asked for again.
        let image = try await loader.load(id: "again", task: task)

        // Then: it starts a fresh request instead of joining the cancelled one.
        #expect(image.size.width > 0)
        #expect(await probe.startCount == 2)
    }
}

// MARK: - Test helpers

private struct StubImageTask: RequestTask {

    let onResult: @Sendable () async throws -> TaskResult<Data>

    func result() async throws -> TaskResult<Data> {
        try await onResult()
    }
}

private actor RequestProbe {

    private(set) var startCount = 0
    private(set) var wasCancelled = false

    var didStart: Bool { startCount > 0 }

    func started() {
        startCount += 1
    }

    func cancelled() {
        wasCancelled = true
    }
}

/// Holds a request until the test lets it finish.
private actor Gate {

    private(set) var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else {
            return
        }

        await withCheckedContinuation { waiting.append($0) }
    }

    func open() {
        isOpen = true

        for continuation in waiting {
            continuation.resume()
        }

        waiting = []
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
