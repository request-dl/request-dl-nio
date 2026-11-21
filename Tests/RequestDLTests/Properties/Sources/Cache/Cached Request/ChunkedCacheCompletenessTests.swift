//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

/// What `.urlSession` is allowed to write to the cache.
///
/// CFNetwork reports a chunked body that was cut exactly on a chunk boundary as a complete,
/// successful response (see `ChunkedTruncationTests`), so on `.urlSession` a response with no
/// `Content-Length` has nothing that proves it is whole. Storing it would keep a truncated body
/// that no later request ever revalidates: the entry has no length to check against. Such a
/// response is delivered to the caller as usual and left out of the cache.
///
/// The `.nio` executors do prove it, with the zero-length chunk that ends the body, and a body
/// that ended without one fails the request, so they keep caching.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct ChunkedCacheCompletenessTests {

    private static let length = 262_144

    /// A multiple of the server's 16 KiB chunk size: every chunk sent so far is whole.
    private static let cutOnAChunkBoundary = 8 * 16_384

    private typealias Executor = TransferTestExecutor

    private struct Outcome {
        let bytes: Int?
        let error: (any Error)?
        let cached: Int?
        let requests: [TransferServer.ReceivedRequest]
    }

    /// One request for `/resource` with the cache on, and the size of whatever the cache holds for
    /// it once the write has settled.
    private static func run(
        against server: TransferServer,
        executor: Executor,
        probes: Bool = false,
        capacity: Int64 = 8 * 1_024 * 1_024,
        expectingRequests expected: Int = 1
    ) async -> Outcome {
        let dataCache = DataCache(suiteName: UUID().uuidString)
        await dataCache.removeAll()

        let session = executor.pinnedSession
            .cachePolicy(.all)
            .cacheStrategy(.returnCachedDataElseLoad)
            .cacheCompletenessProbe(probes)
            .cache(memoryCapacity: capacity, diskCapacity: capacity, url: dataCache.directoryURL)

        var bytes: Int?
        var failure: (any Error)?

        do {
            let result = try await DataTask {
                session
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Path("/resource")
            }
            .result()

            bytes = result.payload.count
        } catch {
            failure = error
        }

        await dataCache.waitUntilIdle()

        let cached = await DataCache(url: dataCache.directoryURL).getCachedData(
            forKey: "http://127.0.0.1:\(server.port)/resource",
            policy: .all
        )

        await dataCache.removeAll()

        // The server records a request once it has finished writing the answer, which a client
        // that has read all of it can get ahead of. Waited for here, so a slow runner does not
        // read the log one entry short.
        try? await eventually { server.requests.count >= expected }

        return Outcome(
            bytes: bytes,
            error: failure,
            cached: cached.map { $0.buffer.readableBytes },
            requests: server.requests
        )
    }

    // MARK: - .urlSession

    #if canImport(Darwin)
    @Test
    private func chunkedCutOnABoundary_isDeliveredButNotCached_onURLSession() async throws {
        try await withTransferServer(.init(length: Self.length, isChunked: true)) { server in
            server.dropPlan = [Self.cutOnAChunkBoundary]

            let outcome = await Self.run(against: server, executor: .urlSession)

            // The caller gets what arrived. CFNetwork says it is the whole response.
            #expect(outcome.bytes == Self.cutOnAChunkBoundary)
            // The cache does not keep a body nothing proves complete.
            #expect(outcome.cached == nil)
        }
    }

    @Test
    private func completeChunked_isDeliveredButNotCached_onURLSession() async throws {
        try await withTransferServer(.init(length: Self.length, isChunked: true)) { server in
            let outcome = await Self.run(against: server, executor: .urlSession)

            #expect(outcome.bytes == Self.length)
            #expect(outcome.cached == nil)
        }
    }

    @Test
    private func contentLength_isStillCached_onURLSession() async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            let outcome = await Self.run(against: server, executor: .urlSession)

            #expect(outcome.bytes == Self.length)
            #expect(outcome.cached == Self.length)
        }
    }
    #endif

    // MARK: - .urlSession, with the probe

    #if canImport(Darwin)
    @Test
    private func probe_whenTheBodyWasCut_asksForTheNextByteAndDoesNotCache() async throws {
        try await withTransferServer(.init(length: Self.length, isChunked: true)) { server in
            server.dropPlan = [Self.cutOnAChunkBoundary]

            let outcome = await Self.run(against: server, executor: .urlSession, probes: true, expectingRequests: 2)

            #expect(outcome.bytes == Self.cutOnAChunkBoundary)
            #expect(outcome.requests.count == 2)
            #expect(
                outcome.requests.last?.header("Range")
                    == "bytes=\(Self.cutOnAChunkBoundary)-\(Self.cutOnAChunkBoundary)"
            )
            // There was a byte after them: the server answered with it.
            #expect(outcome.requests.last?.status == 206)
            #expect(outcome.cached == nil)
        }
    }

    @Test
    private func probe_whenTheBodyWasWhole_cachesIt() async throws {
        try await withTransferServer(.init(length: Self.length, isChunked: true)) { server in
            let outcome = await Self.run(against: server, executor: .urlSession, probes: true, expectingRequests: 2)

            #expect(outcome.bytes == Self.length)
            #expect(outcome.requests.count == 2)
            #expect(outcome.requests.last?.header("Range") == "bytes=\(Self.length)-\(Self.length)")
            #expect(outcome.requests.last?.header("If-Range") != nil)
            #expect(outcome.requests.last?.status == 416)
            #expect(outcome.cached == Self.length)
        }
    }

    @Test
    private func probe_whenTheServerDoesNotAdvertiseRanges_doesNotAskAndDoesNotCache() async throws {
        try await withTransferServer(.init(length: Self.length, supportsRanges: false, isChunked: true)) { server in
            let outcome = await Self.run(against: server, executor: .urlSession, probes: true)

            #expect(outcome.bytes == Self.length)
            #expect(outcome.requests.count == 1)
            #expect(outcome.cached == nil)
        }
    }

    @Test
    private func probe_whenNoTierKeptTheBody_doesNotAsk() async throws {
        // Given: a chunked body that outgrows both tiers, so nothing is left to complete.
        try await withTransferServer(.init(length: Self.length, isChunked: true)) { server in
            // When
            let outcome = await Self.run(against: server, executor: .urlSession, probes: true, capacity: 16_384)

            // Then: the caller has the body, and the one request is the only one made.
            #expect(outcome.bytes == Self.length)
            #expect(outcome.requests.count == 1)
            #expect(outcome.cached == nil)
        }
    }

    @Test
    private func probe_whenTheResponseHasALength_isNotUsed() async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            let outcome = await Self.run(against: server, executor: .urlSession, probes: true)

            #expect(outcome.requests.count == 1)
            #expect(outcome.cached == Self.length)
        }
    }
    #endif

    // MARK: - .nio

    #if canImport(NIOCore)
    @Test
    private func completeChunked_isCached_onNIO() async throws {
        try await withTransferServer(.init(length: Self.length, isChunked: true)) { server in
            let outcome = await Self.run(against: server, executor: .nio)

            #expect(outcome.bytes == Self.length)
            #expect(outcome.cached == Self.length)
        }
    }

    @Test
    private func probe_isNotUsed_onNIO() async throws {
        try await withTransferServer(.init(length: Self.length, isChunked: true)) { server in
            let outcome = await Self.run(against: server, executor: .nio, probes: true)

            #expect(outcome.requests.count == 1)
            #expect(outcome.cached == Self.length)
        }
    }

    @Test
    private func chunkedCutOnABoundary_failsAndIsNotCached_onNIO() async throws {
        try await withTransferServer(.init(length: Self.length, isChunked: true)) { server in
            server.dropPlan = [Self.cutOnAChunkBoundary]

            let outcome = await Self.run(against: server, executor: .nio)

            #expect(outcome.error != nil)
            #expect(outcome.cached == nil)
        }
    }
    #endif
}
