//
// See LICENSE for this package's licensing information.
//

import Logging
import RequestDLInternals
import SwiftAsyncStream
import SwiftAsyncTesting
import Testing

import class Foundation.FileManager

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
import struct Foundation.URL
import struct Foundation.Date
import class Foundation.JSONDecoder
import class Foundation.JSONEncoder
#endif

@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct CachedRequestTests {

    final class TestState: Sendable {

        let certificate = Certificates().server()
        let dataCache: DataCache
        let output = String.randomString(length: 64)
        let localServer: LocalServer
        let uri: String

        init() async throws {
            let uniqueKey = UUID().uuidString
            uri = "/" + uniqueKey
            dataCache = .init(suiteName: uniqueKey)
            localServer = try await LocalServer(.standard)
            localServer.cleanup(at: uri)

            await dataCache.removeAll()
            dataCache.memoryCapacity = 8 * 1_024 * 1_024
            dataCache.diskCapacity = 64 * 1_024 * 1_024
        }

        deinit {
            let dataCache = self.dataCache
            Task.detached { await dataCache.removeAll() }

            dataCache.memoryCapacity = .zero
            dataCache.diskCapacity = .zero

            localServer.cleanup(at: uri)
        }
    }

    @Test
    func cache_whenNoCacheOnIgnoresCachedDataStrategy() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(noCache: true),
            cacheStrategy: .ignoreCachedData
        )

        await testState.dataCache.waitUntilIdle()

        let cachedData = await DataCache(url: testState.dataCache.directoryURL).getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(cachedData == nil)
        #expect(response.head.headers.first(name: "Cache-Control") == "no-cache")
    }

    @Test
    func cache_whenNoCacheOnIgnoresCachedDataStrategyWithPreviousCache() async throws {
        let testState = try await TestState()
        // Given
        let cacheData = await mockCachedData(makeHeaders(eTag: UUID()))
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(noCache: true),
            cacheStrategy: .ignoreCachedData
        )

        await testState.dataCache.waitUntilIdle()

        let updatedCachedData = await DataCache(url: testState.dataCache.directoryURL).getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(updatedCachedData?.response == cacheData.response)
        #expect(response.head.headers.first(name: "Cache-Control") == "no-cache")
    }

    @Test
    func cache_whenUseCachedDataOnlyStrategyWithoutCache() async throws {
        let testState = try await TestState()
        // Given
        var thrownError: Error?

        // When
        do {
            _ = try await performCacheRequest(
                testState: testState,
                headers: makeHeaders(),
                cacheStrategy: .useCachedDataOnly
            )
        } catch {
            thrownError = error
        }

        // Then
        #expect(thrownError is EmptyCachedDataError)
    }

    @Test
    func cache_whenUseCachedDataOnlyStrategyWithValidCacheMaxAge() async throws {
        let testState = try await TestState()
        // A wide `max-age`, not the two seconds
        // `cache_whenUseCachedDataOnlyStrategyWithInvalidCacheMaxAge` waits past. This test never
        // sleeps, so its window only has to outlast the actual request/response round trip below,
        // which on a loaded CI simulator alone can exceed a couple of seconds.
        let cacheData = await mockCachedData(makeHeaders(maxAgeSeconds: 3_600))
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: UUID()),
            cacheStrategy: .useCachedDataOnly
        )

        await testState.dataCache.waitUntilIdle()

        let updatedCachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(updatedCachedData?.response == cacheData.response)
        #expect(response.head == cacheData.response)
    }

    @Test
    func cache_whenUseCachedDataOnlyStrategyWithInvalidCacheMaxAge() async throws {
        let testState = try await TestState()
        let cacheData = await mockCachedData(makeHeaders())
        let cacheKey = "https://localhost:8888" + testState.uri
        var thrownError: Error?

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        try await waitCacheExpiration()

        do {
            _ = try await performCacheRequest(
                testState: testState,
                headers: makeHeaders(),
                cacheStrategy: .useCachedDataOnly
            )
        } catch {
            thrownError = error
        }

        // Then
        #expect(thrownError is EmptyCachedDataError)
    }

    /// `isCachedDataValid`'s max-age freshness check must not be skipped for
    /// `Cache-Control: max-age=0`, a common, valid directive meaning "cacheable, but revalidate
    /// before every reuse". It has to be treated as immediately stale, since otherwise (with no
    /// `Expires` header, the common modern pattern of relying on `Cache-Control` alone) the entry
    /// would be reported valid forever. No sleep needed here, unlike
    /// `cache_whenUseCachedDataOnlyStrategyWithInvalidCacheMaxAge`: `max-age=0` must already be
    /// stale the instant it's checked.
    @Test
    func cache_whenUseCachedDataOnlyStrategyWithMaxAgeZero_treatsCacheAsInvalid() async throws {
        let testState = try await TestState()
        let cacheData = await mockCachedData(makeHeaders(maxAgeSeconds: 0))
        let cacheKey = "https://localhost:8888" + testState.uri
        var thrownError: Error?

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        do {
            _ = try await performCacheRequest(
                testState: testState,
                headers: makeHeaders(),
                cacheStrategy: .useCachedDataOnly
            )
        } catch {
            thrownError = error
        }

        // Then
        #expect(thrownError is EmptyCachedDataError)
    }

    @Test
    func cache_whenUseCachedDataOnlyStrategyWithValidCacheExpires() async throws {
        let testState = try await TestState()
        // A wide `Expires` window, not the two seconds
        // `cache_whenUseCachedDataOnlyStrategyWithInvalidCacheExpires` waits past. This test never
        // sleeps, so its window only has to outlast the actual request/response round trip below,
        // which on a loaded CI simulator alone can exceed a couple of seconds.
        let cacheData = await mockCachedData(makeHeaders(maxAge: false, expiresOffsetSeconds: 3_600))
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: UUID()),
            cacheStrategy: .useCachedDataOnly
        )

        await testState.dataCache.waitUntilIdle()

        let updatedCachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(updatedCachedData?.response == cacheData.response)
        #expect(response.head == cacheData.response)
    }

    @Test
    func cache_whenUseCachedDataOnlyStrategyWithInvalidCacheExpires() async throws {
        let testState = try await TestState()
        let cacheData = await mockCachedData(makeHeaders(maxAge: false))
        let cacheKey = "https://localhost:8888" + testState.uri
        var thrownError: Error?

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        try await waitCacheExpiration()

        do {
            _ = try await performCacheRequest(
                testState: testState,
                headers: makeHeaders(),
                cacheStrategy: .useCachedDataOnly
            )
        } catch {
            thrownError = error
        }

        // Then
        #expect(thrownError is EmptyCachedDataError)
    }

    @Test
    func cache_whenReturnCachedDataElseLoadWithValidCache() async throws {
        let testState = try await TestState()
        // A wide `max-age`: this test never sleeps, so its window only has to outlast the
        // actual request/response round trip below, not a fixed couple of seconds. See the
        // identical reasoning on `cache_whenUseCachedDataOnlyStrategyWithValidCacheMaxAge`.
        let cacheData = await mockCachedData(makeHeaders(maxAgeSeconds: 3_600))
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: UUID()),
            cacheStrategy: .returnCachedDataElseLoad
        )

        await testState.dataCache.waitUntilIdle()

        let updatedCachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(updatedCachedData?.response == cacheData.response)
        #expect(response.head == cacheData.response)
    }

    @Test
    func cache_whenEncryptionKeySetWithValidCache_returnsCachedDataRatherThanRefetching() async throws {
        let testState = try await TestState()
        let encryptionKey = DataCache.EncryptionKey(Data(repeating: 0x07, count: 32))
        testState.dataCache.encryptionKey = encryptionKey

        // `policy: .disk`: the memory tier stays unencrypted and is deliberately out of scope, so a
        // `.all`-policy entry would let a memory hit shadow the disk read entirely and this test
        // would pass regardless of whether the encrypted disk path works at all. Disk-only forces
        // the read this test actually cares about, which also means it has no memory-tier fast path
        // to fall back on, so a wide `max-age` matters here too: see the reasoning on
        // `cache_whenUseCachedDataOnlyStrategyWithValidCacheMaxAge`.
        let cacheData = await mockCachedData(makeHeaders(maxAgeSeconds: 3_600), policy: .disk)
        let cacheKey = "https://localhost:8888" + testState.uri

        // When: seeded through the real encrypted disk tier: `setCachedData` routes through
        // `DiskStorage.allocateBuffer`, honoring whatever key is set on the shared `Storage` this
        // directory resolves to, exactly like a real write would.
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        // Passed through the request too, the way an app configuring encryption per request would.
        // (Leaving it only on `testState.dataCache` works as well: a request that doesn't specify a
        // key leaves the shared `Storage`'s key alone, see `CachePropertiesTests`'
        // `cache_whenEncryptionKeyNotSpecified_preservesTheCachesExistingKey`.)
        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: UUID()),
            cacheStrategy: .returnCachedDataElseLoad,
            encryptionKey: encryptionKey
        )

        await testState.dataCache.waitUntilIdle()

        let updatedCachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then: this is the critical test for at-rest encryption on the disk tier.
        // `isCachedDataValid` rejects an entry whose `buffer.readableBytes` doesn't match the
        // origin's `Content-Length`: if `EncryptedFileBufferURL.writtenBytes` ever reported the
        // real (ciphertext-plus-framing) file size instead of the logical plaintext size, that
        // check would fail for every encrypted entry, permanently, and every request would fall
        // through to a live fetch instead of ever hitting the cache. `cacheData.response` is
        // synthetic (a fixed URL/status/headers that bear no resemblance to what the local test
        // server actually returns), so equality here can only hold if the seeded, encrypted entry
        // was read back and judged valid; a genuine re-fetch could not produce a matching value.
        #expect(updatedCachedData?.response == cacheData.response)
        #expect(response.head == cacheData.response)
    }

    /// An entry that cannot be read is a miss, as the documentation of the encrypted buffers
    /// promises: the request goes out instead of failing with a stored body nobody can trust.
    @Test
    func cache_whenAnEncryptedEntryFailsToAuthenticate_isServedFromTheNetworkInstead() async throws {
        let testState = try await TestState()
        let encryptionKey = DataCache.EncryptionKey(Data(repeating: 0x07, count: 32))
        testState.dataCache.encryptionKey = encryptionKey

        // Given: a valid entry on disk, whose last byte is then flipped. The size is the same, so
        // the lookup still judges it complete, and only reading it back can tell.
        let cacheData = await mockCachedData(makeHeaders(maxAgeSeconds: 3_600), policy: .disk)
        let cacheKey = "https://localhost:8888" + testState.uri

        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)
        await testState.dataCache.waitUntilIdle()

        try flipLastByteOfStoredBody(in: testState.dataCache.directoryURL)

        // When
        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: UUID()),
            cacheStrategy: .returnCachedDataElseLoad,
            encryptionKey: encryptionKey
        )

        // Then: what the server answered, not the stored body and not an error.
        #expect(try responseText(response) == testState.output)
    }

    /// A chunk of an encrypted entry is authenticated whole, so the first piece vouches for the
    /// first 4 MiB only. A body that fails later cannot be taken back once it started, but the
    /// entry must not stay: the next request would read the same first piece, pass, and fail at
    /// the same place for as long as the entry is fresh.
    @Test
    func cache_whenALaterChunkOfAnEncryptedEntryFails_theNextRequestIsServedFromTheNetwork() async throws {
        let testState = try await TestState()
        let encryptionKey = DataCache.EncryptionKey(Data(repeating: 0x07, count: 32))
        testState.dataCache.encryptionKey = encryptionKey

        // Given: an entry of two chunks, the last byte of the second one flipped.
        let size = Internals.EncryptedFileStreamBuffer.chunkPlaintextSize + 100_000
        let cacheData = await mockCachedData(
            makeHeaders(maxAgeSeconds: 3_600),
            policy: .disk,
            body: Data(repeating: 0x5A, count: size)
        )
        let cacheKey = "https://localhost:8888" + testState.uri

        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)
        await testState.dataCache.waitUntilIdle()

        try flipLastByteOfStoredBody(in: testState.dataCache.directoryURL)

        // When: the first request starts from the entry and fails part of the way.
        var firstError: (any Error)?

        do {
            _ = try await performCacheRequest(
                testState: testState,
                headers: makeHeaders(eTag: UUID()),
                cacheStrategy: .returnCachedDataElseLoad,
                encryptionKey: encryptionKey
            )
        } catch {
            firstError = error
        }

        // Then: it failed, and the entry went with it.
        #expect(firstError != nil)

        let second = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: UUID()),
            cacheStrategy: .returnCachedDataElseLoad,
            encryptionKey: encryptionKey
        )

        #expect(try responseText(second) == testState.output)
    }

    @Test
    func cache_whenReturnCachedDataElseLoadWithInvalidCache() async throws {
        let testState = try await TestState()
        let cacheData = await mockCachedData(makeHeaders())
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        try await waitCacheExpiration()

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(),
            cacheStrategy: .returnCachedDataElseLoad
        )

        await testState.dataCache.waitUntilIdle()

        let updatedCachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(updatedCachedData?.response != cacheData.response)
        #expect(response.head != cacheData.response)
    }

    @Test
    func cache_whenReloadAndValidateCachedDataWithValidCache() async throws {
        let testState = try await TestState()
        let eTag = UUID()
        // A freshness window far wider than the request can take, on both sides: the cached
        // entry has to still be fresh when the revalidation finishes, and the server's answer has
        // to carry the same directive, or revalidating would refresh the entry's `max-age` and
        // the comparison below would see a changed one. With the default two seconds, a runner
        // slow enough to take longer than that between caching the entry and validating it found
        // the entry expired: the revalidation `HEAD` had already used up the server's one
        // response, so the refetch got the server's default one instead.
        let cacheData = await mockCachedData(makeHeaders(eTag: eTag, maxAgeSeconds: 3_600))
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: eTag, maxAgeSeconds: 3_600),
            cacheStrategy: .reloadAndValidateCachedData
        )

        await testState.dataCache.waitUntilIdle()

        let updatedCachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(updatedCachedData?.response == cacheData.response)
        #expect(response.head == cacheData.response)
    }

    @Test
    func cache_whenReloadAndValidateCachedDataWithInvalidCache() async throws {
        let testState = try await TestState()
        let eTag = UUID()
        let cacheData = await mockCachedData(makeHeaders())
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        try await waitCacheExpiration()

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: eTag),
            cacheStrategy: .reloadAndValidateCachedData
        )

        await testState.dataCache.waitUntilIdle()

        let updatedCachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(updatedCachedData?.response != cacheData.response)
        #expect(response.head != cacheData.response)
    }

    // MARK: - Metrics

    /// A response served from the cache is a transaction of its own, with the source to say so, and
    /// not an absence of metrics: nothing crossed the wire, so there is no connection.
    @Test
    func cache_whenServedFromTheCache_reportsACacheTransaction() async throws {
        // Given
        let testState = try await TestState()
        let cacheKey = "https://localhost:8888" + testState.uri

        await testState.dataCache.setCachedData(
            await mockCachedData(makeHeaders(maxAgeSeconds: 3_600)),
            forKey: cacheKey
        )

        // When
        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAgeSeconds: 3_600),
            cacheStrategy: .returnCachedDataElseLoad
        )

        // Then
        let transactions = try #require(response.metrics).transactions
        #expect(transactions.map(\.source) == [.cache])

        let transaction = try #require(transactions.first)
        #expect(transaction.connection == nil)
        #expect(transaction.url?.absoluteString == cacheKey)
        #expect(transaction.responseStart != nil)
        #expect(transaction.error == nil)
    }

    @Test
    func cache_whenNothingIsCached_reportsOnlyTheNetworkTransaction() async throws {
        // Given
        let testState = try await TestState()

        // When
        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAgeSeconds: 3_600),
            cacheStrategy: .returnCachedDataElseLoad
        )

        // Then
        #expect(try #require(response.metrics).transactions.map(\.source) == [.network])
    }

    /// The conditional request is a request the caller did not make. It comes first, marked as such,
    /// and the cached response it confirmed after it.
    @Test
    func cache_whenRevalidationConfirmsTheCache_reportsTheRevalidationThenTheCache() async throws {
        // Given
        let testState = try await TestState()
        let eTag = UUID()
        let cacheKey = "https://localhost:8888" + testState.uri

        await testState.dataCache.setCachedData(
            await mockCachedData(makeHeaders(eTag: eTag, maxAgeSeconds: 3_600)),
            forKey: cacheKey
        )

        // When
        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: eTag, maxAgeSeconds: 3_600),
            cacheStrategy: .reloadAndValidateCachedData
        )

        // Then
        let transactions = try #require(response.metrics).transactions
        #expect(transactions.map(\.source) == [.revalidation, .cache])

        let revalidation = try #require(transactions.first)
        #expect(revalidation.connection != nil)
        #expect(revalidation.responseStart != nil)
        #expect(transactions.last?.connection == nil)
    }

    /// A revalidation that does not settle the matter is followed by the request itself, which is
    /// what the response then is.
    @Test
    func cache_whenRevalidationFindsTheCacheInvalid_reportsTheRevalidationThenTheRequest() async throws {
        // Given
        let testState = try await TestState()
        let eTag = UUID()
        let cacheKey = "https://localhost:8888" + testState.uri

        await testState.dataCache.setCachedData(
            await mockCachedData(makeHeaders()),
            forKey: cacheKey
        )

        try await waitCacheExpiration()

        // When
        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: eTag),
            cacheStrategy: .reloadAndValidateCachedData
        )

        // Then
        let transactions = try #require(response.metrics).transactions
        #expect(transactions.map(\.source) == [.revalidation, .network])
        #expect(transactions.allSatisfy { $0.connection != nil })
    }

    /// The conditional request goes through each executor's own `revalidationHead`, so each one has to
    /// record it as a revalidation.
    private static var executors: [Session.Executor] {
        var executors: [Session.Executor] = []

        #if canImport(Darwin)
        executors.append(.urlSession)
        #endif

        #if canImport(NIOCore)
        executors.append(.nio)
        #endif

        return executors
    }

    @Test(arguments: executors)
    private func cache_whenRevalidationConfirmsTheCache_reportsItOnEveryExecutor(
        _ executor: Session.Executor
    ) async throws {
        // Given
        let testState = try await TestState()
        let eTag = UUID()
        let cacheKey = "https://localhost:8888" + testState.uri

        await testState.dataCache.setCachedData(
            await mockCachedData(makeHeaders(eTag: eTag, maxAgeSeconds: 3_600)),
            forKey: cacheKey
        )

        // When
        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: eTag, maxAgeSeconds: 3_600),
            cacheStrategy: .reloadAndValidateCachedData,
            executor: executor
        )

        // Then
        let transactions = try #require(response.metrics).transactions
        #expect(transactions.map(\.source) == [.revalidation, .cache])
        #expect(transactions.first?.connection != nil)
        #expect(transactions.first?.responseStart != nil)
    }

    @Test(arguments: executors)
    private func cache_whenRevalidationFindsTheCacheInvalid_reportsItOnEveryExecutor(
        _ executor: Session.Executor
    ) async throws {
        // Given
        let testState = try await TestState()
        let cacheKey = "https://localhost:8888" + testState.uri

        await testState.dataCache.setCachedData(
            await mockCachedData(makeHeaders()),
            forKey: cacheKey
        )

        try await waitCacheExpiration()

        // When
        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: UUID()),
            cacheStrategy: .reloadAndValidateCachedData,
            executor: executor
        )

        // Then: the revalidation first, then the request itself, whose transaction the executor recorded.
        let transactions = try #require(response.metrics).transactions
        #expect(transactions.map(\.source) == [.revalidation, .network])
    }

    @Test
    func cache_whenCacheDisabledByPolicy_withUseCachedDataOnlyStrategy() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // When
        var thrownError: Error?

        do {
            _ = try await performCacheRequest(
                testState: testState,
                headers: makeHeaders(),
                cachePolicy: [],
                cacheStrategy: .useCachedDataOnly
            )
        } catch {
            thrownError = error
        }

        // Then
        #expect(thrownError is EmptyCachedDataError)
    }

    /// Only a response whose status is cacheable by default (RFC 9111 §4.2.2) may be stored. A
    /// cached entry with no `max-age`/`Expires` is treated as valid indefinitely, so storing a
    /// transient `503` meant `.returnCachedDataElseLoad` replayed that outage on every later
    /// request, without ever asking the network again.
    @Test
    func cache_whenResponseIsTransientServerError_isNotStored() async throws {
        let testState = try await TestState()
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        _ = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAge: false, expiresOffsetSeconds: 3_600),
            status: .serviceUnavailable,
            cacheStrategy: .returnCachedDataElseLoad
        )

        await testState.dataCache.waitUntilIdle()

        let cachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(cachedData == nil)
    }

    /// `getUpdatedHeadersForCache`'s 304 branch must return the fresh 304 response's own headers,
    /// not `cachedData.response.headers` (the stale, already-cached ones). Otherwise
    /// `updateCacheHeaders` would always compare the cached headers against themselves, find no
    /// difference, and `validateCachedData` would return the cache entry completely unmodified:
    /// `CachedResponse.date` would never refresh, so a 304 could never extend an already-cached
    /// entry's freshness (RFC 9111 §4.3.4), the one thing revalidation exists to do. A 304
    /// carrying a genuinely different `Cache-Control`/`Expires` must be adopted, the same as the
    /// non-304 fallback path does (see
    /// `cache_whenReloadAndValidateCachedDataHeadersChange_updatesCachedHeaders` below).
    @Test
    func cache_whenReloadAndValidateCachedDataReceives304_adoptsFreshCacheDirectives() async throws {
        let testState = try await TestState()
        let eTag = UUID()
        let cacheData = await mockCachedData(makeHeaders(eTag: eTag))
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            testState: testState,
            // A real 304 carries no meaningful body, but it can (and here does) carry an updated
            // `Cache-Control`/`Expires`, deliberately different from the cached entry's, to
            // confirm the 304 branch now adopts them instead of reusing the stale cached values.
            headers: makeHeaders(eTag: eTag, maxAge: false, expiresOffsetSeconds: 3_600),
            status: .notModified,
            cacheStrategy: .reloadAndValidateCachedData
        )

        await testState.dataCache.waitUntilIdle()

        let updatedCachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(updatedCachedData?.response.headers.first(name: "Cache-Control") == "public")
        #expect(updatedCachedData?.response.headers.first(name: "Expires") != nil)
        #expect(updatedCachedData?.response != cacheData.response)
        #expect(response.head.headers.first(name: "Cache-Control") == "public")
    }

    @Test
    func cache_whenReloadAndValidateCachedDataHeadersChange_updatesCachedHeaders() async throws {
        let testState = try await TestState()
        let eTag = UUID()
        let cacheData = await mockCachedData(makeHeaders(eTag: eTag))
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        // A non-304, same-`ETag` response takes the fallback path in `getUpdatedHeadersForCache`
        // that hands back the fresh response's own headers instead of the cached ones: the only
        // reachable route (given this fixture's server always answers 200) to a genuine
        // `Cache-Control` change between the cached entry and what revalidation just returned.
        let response = try await performCacheRequest(
            testState: testState,
            headers: [
                ("ETag", String(describing: eTag)),
                ("Cache-Control", "public, max-age=1000"),
            ],
            cacheStrategy: .reloadAndValidateCachedData
        )

        await testState.dataCache.waitUntilIdle()

        let updatedCachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(updatedCachedData?.response.headers.first(name: "Cache-Control") == "public, max-age=1000")
        #expect(updatedCachedData?.response != cacheData.response)
        #expect(response.head.headers.first(name: "Cache-Control") == "public, max-age=1000")
    }

    @Test
    func cache_whenCachedContentLengthDoesNotMatchStoredData_isInvalid() async throws {
        let testState = try await TestState()
        let eTag = UUID()
        // `Content-Length` deliberately overstated relative to the actual stored payload, so
        // `isCachedDataValid`'s `cachedData.buffer.readableBytes != contentLength` check fails
        // the entry regardless of `max-age`/`Expires`.
        let cacheData = await mockCachedData(
            makeHeaders(eTag: eTag),
            contentLengthOverride: 999_999
        )
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: eTag),
            cacheStrategy: .returnCachedDataElseLoad
        )

        await testState.dataCache.waitUntilIdle()

        let updatedCachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(updatedCachedData?.response != cacheData.response)
        #expect(response.head != cacheData.response)
    }

    @Test
    func cache_whenCachedResponseHasNoContentLength_isStillValid() async throws {
        let testState = try await TestState()
        let eTag = UUID()
        // No "Content-Length" header at all, the exact shape a chunked-transfer or HTTP/2
        // response leaves behind.
        // `maxAgeSeconds` wide enough that the entry is still fresh when it is looked up, however
        // slow the runner: this test is about the missing `Content-Length`, not about expiry.
        let cacheData = await mockCachedData(
            makeHeaders(eTag: eTag, maxAgeSeconds: 3_600),
            includeContentLength: false
        )
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: eTag),
            cacheStrategy: .returnCachedDataElseLoad
        )

        await testState.dataCache.waitUntilIdle()

        let updatedCachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then: served from cache, not refetched and replaced.
        #expect(updatedCachedData?.response == cacheData.response)
        #expect(response.head == cacheData.response)
    }

    @Test
    func cache_whenCachedResponseHasContentEncoding_isStillValidDespiteContentLengthMismatch() async throws {
        let testState = try await TestState()
        let eTag = UUID()
        // "Content-Encoding: gzip" alongside a "Content-Length" that does not match the cached
        // bytes. This is the exact mismatch a transparently-decompressed response leaves behind:
        // the cached bytes are the decoded body, but `Content-Length` still reflects the
        // compressed size on the wire, since neither `NIOHTTPResponseDecompressor` nor
        // CFNetwork's own decoding strips the header.
        // `maxAgeSeconds` wide enough that the entry is still fresh when it is looked up, however
        // slow the runner: this test is about the `Content-Length` mismatch, not about expiry.
        let cacheData = await mockCachedData(
            makeHeaders(eTag: eTag, maxAgeSeconds: 3_600) + [("Content-Encoding", "gzip")],
            contentLengthOverride: 1
        )
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: eTag),
            cacheStrategy: .returnCachedDataElseLoad
        )

        await testState.dataCache.waitUntilIdle()

        let updatedCachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then: served from cache, not refetched and replaced.
        #expect(updatedCachedData?.response == cacheData.response)
        #expect(response.head == cacheData.response)
    }

    @Test
    func cache_whenCapacityTooSmallForResponse_skipsCaching() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        // A capacity smaller than any real response makes `MemoryStorage`/`DiskStorage`
        // decline the entry for size, so `cacheIfNeeded` writes nowhere and nothing ends up
        // cached. It is passed explicitly through `.cache(memoryCapacity:diskCapacity:url:)` rather
        // than mutated on `testState.dataCache` directly, since `Internals.CacheConfiguration`
        // floors any unset/zero capacity back up to 2 MiB (see its `minimumCapacity`), which
        // would silently undo an external override made before the request runs.
        _ = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(),
            cacheStrategy: .returnCachedDataElseLoad,
            memoryCapacity: 1,
            diskCapacity: 1
        )

        await testState.dataCache.waitUntilIdle()

        let cachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(cachedData == nil)
    }

    @Test
    func cache_whenLoggerEnabledAtTraceLevel_logsCachedResponseSizeMetadata() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        final class RecordBox: @unchecked Sendable {
            var records: [TestLogHandler.LogRecord] {
                lock.withLock { _records }
            }

            private let lock = SwiftAsyncStream.Lock()
            private var _records: [TestLogHandler.LogRecord] = []

            func append(_ record: TestLogHandler.LogRecord) {
                lock.withLock { _records.append(record) }
            }
        }

        let recordBox = RecordBox()

        // When
        _ = try await Logger.withTesting(
            level: .trace,
            recorded: { recordBox.append($0) },
            perform: { logger in
                try await performCacheRequest(
                    testState: testState,
                    headers: makeHeaders(),
                    cacheStrategy: .returnCachedDataElseLoad,
                    logger: logger
                )
            }
        )

        await testState.dataCache.waitUntilIdle()

        // Then
        let savedRecord = recordBox.records.first { $0.metadata["size_bytes"] != nil }
        #expect(savedRecord != nil)
    }

    @Test
    @available(*, deprecated)
    func cache_whenOnlyIfCachedRequestDirective_escalatesToUseCachedDataOnly() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        var thrownError: Error?

        // When
        // `.returnCachedDataElseLoad` alone would hit the network since there's no cached
        // entry yet: `CacheHeader().onlyIfCached(true)` must escalate this to behave like
        // `.useCachedDataOnly` instead.
        do {
            _ = try await performCacheRequest(
                testState: testState,
                headers: makeHeaders(),
                cacheStrategy: .returnCachedDataElseLoad,
                cacheHeader: CacheHeader().onlyIfCached(true)
            )
        } catch {
            thrownError = error
        }

        // Then
        #expect(thrownError is EmptyCachedDataError)
    }

    @Test
    @available(*, deprecated)
    func cache_whenOnlyIfCachedRequestDirective_withCachingDisabled_doesNotForceLocalCacheOnly() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // When
        // `only-if-cached` addresses caches downstream of this client (a CDN or proxy): with no
        // `.cachePolicy(_:)` configured, this package's own on-disk cache was never opted into,
        // so the directive must not force `EmptyCachedDataError` locally; the request should just
        // go through normally.
        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(),
            cachePolicy: [],
            cacheStrategy: .returnCachedDataElseLoad,
            cacheHeader: CacheHeader().onlyIfCached(true)
        )

        // Then
        #expect(response.head.status.code == 200)
    }

    @Test
    func cache_whenNoCacheRequestDirective_escalatesReturnCachedDataElseLoadToRevalidate() async throws {
        let testState = try await TestState()
        let staleETag = UUID()
        let freshETag = UUID()
        let cacheData = await mockCachedData(makeHeaders(eTag: staleETag))
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        // `.returnCachedDataElseLoad` alone would serve the stale cached entry without ever
        // asking the server: `CacheHeader().cached(false)` (`no-cache`) must escalate this to
        // revalidate, so the fresh ETag from the server wins.
        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: freshETag),
            cacheStrategy: .returnCachedDataElseLoad,
            cacheHeader: CacheHeader().cached(false)
        )

        await testState.dataCache.waitUntilIdle()

        let updatedCachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(updatedCachedData?.response != cacheData.response)
        #expect(response.head != cacheData.response)
    }

    @Test
    func cache_whenNoStoreRequestDirective_skipsCaching() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        // The response is cacheable (`public, max-age=...`), but `CacheHeader().stored(false)`
        // (`no-store`) must still prevent it from being written to disk.
        _ = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(),
            cacheStrategy: .returnCachedDataElseLoad,
            cacheHeader: CacheHeader().stored(false)
        )

        await testState.dataCache.waitUntilIdle()

        let cachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(cachedData == nil)
    }

    // MARK: - A response to a request with credentials

    /// A private cache may store a response to a request that carried `Authorization` (RFC 9111
    /// §3.5 restricts only shared caches), which is what callers expect of a client. It is
    /// stored for that credential, not for the URL alone: see the tests below.
    @Test
    func cache_whenRequestHasAuthorization_storesTheResponseWhateverItsCacheControl() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        let cacheKey = "https://localhost:8888" + testState.uri

        // When: `max-age` alone, without `public`, `must-revalidate` or `s-maxage`.
        _ = try await performCacheRequest(
            testState: testState,
            headers: [("Cache-Control", "max-age=1000")],
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Authorization", "Bearer alice-token")]
        )

        await testState.dataCache.waitUntilIdle()

        let cachedData = try #require(
            await testState.dataCache.getCachedData(forKey: cacheKey, policy: .all)
        )

        // Then: stored, for the three credential headers, as digests and never as values.
        let recorded = try #require(cachedData.cachedResponse.varyRequestHeaders)

        #expect(Set(recorded.keys) == ["authorization", "cookie", "proxy-authorization"])
        #expect(recorded["authorization"]?.hasPrefix("sha256:") == true)
        #expect(recorded["cookie"] == "")
        #expect(recorded["proxy-authorization"] == "")
        #expect(recorded.values.allSatisfy { !$0.contains("alice-token") })
    }

    @Test
    func cache_whenRequestHasAuthorization_servesItToTheSameCredential() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        _ = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAgeSeconds: 3_600),
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Authorization", "Bearer alice-token")],
            output: "first"
        )
        await testState.dataCache.waitUntilIdle()

        // When
        let again = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAgeSeconds: 3_600),
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Authorization", "Bearer alice-token")],
            output: "second"
        )

        // Then: from the cache.
        #expect(try responseText(again) == "first")
    }

    /// The reason the credential is part of what has to match: `DataCache` is one store for the
    /// process, and another account signing in must not be given the first one's response.
    @Test
    func cache_whenRequestHasAuthorization_doesNotServeItToAnotherCredential() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        _ = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAgeSeconds: 3_600),
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Authorization", "Bearer alice-token")],
            output: "alice"
        )
        await testState.dataCache.waitUntilIdle()

        // When
        let other = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAgeSeconds: 3_600),
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Authorization", "Bearer bob-token")],
            output: "bob"
        )

        // Then
        #expect(try responseText(other) == "bob")
    }

    @Test
    func cache_whenRequestHasAuthorization_doesNotServeItToARequestWithNone() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        _ = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAgeSeconds: 3_600),
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Authorization", "Bearer alice-token")],
            output: "alice"
        )
        await testState.dataCache.waitUntilIdle()

        // When
        let anonymous = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAgeSeconds: 3_600),
            cacheStrategy: .returnCachedDataElseLoad,
            output: "anonymous"
        )

        // Then
        #expect(try responseText(anonymous) == "anonymous")
    }

    /// The other direction is as it always was: what an anonymous request got is not about any
    /// account, and is given to a request that sends credentials too.
    @Test
    func cache_whenStoredWithoutCredentials_isServedToARequestWithCredentials() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        _ = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAgeSeconds: 3_600),
            cacheStrategy: .returnCachedDataElseLoad,
            output: "first"
        )
        await testState.dataCache.waitUntilIdle()

        // When
        let withCredentials = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAgeSeconds: 3_600),
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Authorization", "Bearer alice-token")],
            output: "second"
        )

        // Then
        #expect(try responseText(withCredentials) == "first")
    }

    /// Companion to the test above: `public` is one of the three directives RFC 7234 §3.2
    /// recognizes as explicit permission to store a response to a credentialed request, so this
    /// one must still be cached.
    @Test
    func cache_whenRequestHasAuthorizationAndResponseIsExplicitlyPublic_stillCaches() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        _ = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(),
            cacheStrategy: .returnCachedDataElseLoad,
            includesAuthorizationHeader: true
        )

        await testState.dataCache.waitUntilIdle()

        let cachedData = await testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(cachedData != nil)
    }

    // MARK: - Two writes to one key

    /// Both requests miss, both go to the network and both write their response to the same key.
    /// Whatever the order they finish in, what the cache serves afterwards is one whole response,
    /// not the start of one and the end of the other, and not an error.
    @Test(arguments: executors)
    func cache_whenTwoRequestsForTheSameKeyRaceToStoreIt_theEntryServedAfterwardsIsWhole(
        _ executor: Session.Executor
    ) async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given: two bodies of the same size, large enough for the two writes to overlap, that
        // differ in every byte. The server answers each request with one of them.
        let size = 2_000_000
        let bodies = [String(repeating: "x", count: size), String(repeating: "y", count: size)]
        let headers = makeHeaders(maxAgeSeconds: 3_600)

        // When
        async let first = performCacheRequest(
            testState: testState,
            headers: headers,
            cacheStrategy: .returnCachedDataElseLoad,
            output: bodies[0],
            executor: executor
        )

        async let second = performCacheRequest(
            testState: testState,
            headers: headers,
            cacheStrategy: .returnCachedDataElseLoad,
            output: bodies[1],
            executor: executor
        )

        let (firstResult, secondResult) = try await (first, second)
        await testState.dataCache.waitUntilIdle()

        let received = [try responseText(firstResult), try responseText(secondResult)]

        // Then: both went to the network, one for each body. A request served from the cache would
        // have been given the body of the other.
        #expect(Set(received) == Set(bodies))

        // And the entry they left is one of the two bodies, whole and not mixed: the server now
        // says something else, so a request that is not served from the cache cannot pass for one
        // that is.
        let third = try await performCacheRequest(
            testState: testState,
            headers: headers,
            cacheStrategy: .returnCachedDataElseLoad,
            output: "from the network",
            executor: executor
        )

        #expect(bodies.contains(try responseText(third)))
    }

    // MARK: - Vary and credentials in the cache key

    /// `DataCache` is keyed by URL alone, so a response's `Vary` has to be checked or a response
    /// that varies on `Cookie` is replayed to a request carrying another account's cookie.
    @Test
    func cache_whenResponseVariesOnACookie_doesNotServeItToADifferentCookie() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given: an entry stored for one cookie.
        let vary = makeHeaders(maxAgeSeconds: 3_600) + [("Vary", "Cookie")]

        _ = try await performCacheRequest(
            testState: testState,
            headers: vary,
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Cookie", "session=alice")],
            output: "alice"
        )
        await testState.dataCache.waitUntilIdle()

        // When: a different cookie asks for the same URL.
        let other = try await performCacheRequest(
            testState: testState,
            headers: vary,
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Cookie", "session=bob")],
            output: "bob"
        )

        // Then
        #expect(try responseText(other) == "bob")
    }

    @Test
    func cache_whenResponseVariesOnACookie_stillServesTheSameCookie() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        let vary = makeHeaders(maxAgeSeconds: 3_600) + [("Vary", "Cookie")]

        _ = try await performCacheRequest(
            testState: testState,
            headers: vary,
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Cookie", "session=alice")],
            output: "first"
        )
        await testState.dataCache.waitUntilIdle()

        // When
        let again = try await performCacheRequest(
            testState: testState,
            headers: vary,
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Cookie", "session=alice")],
            output: "second"
        )

        // Then: answered from the cache, not the network.
        #expect(try responseText(again) == "first")
    }

    /// The common case must keep working: `Vary: Accept-Encoding` is on most CDN responses, and
    /// two requests that agree on it are the same variant.
    @Test
    func cache_whenResponseVariesOnAFieldTheRequestsAgreeOn_stillServesTheCache() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        let vary = makeHeaders(maxAgeSeconds: 3_600) + [("Vary", "Accept-Language, Accept-Encoding")]

        _ = try await performCacheRequest(
            testState: testState,
            headers: vary,
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Accept-Language", "pt-BR")],
            output: "first"
        )
        await testState.dataCache.waitUntilIdle()

        // When
        let same = try await performCacheRequest(
            testState: testState,
            headers: vary,
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Accept-Language", "pt-BR")],
            output: "second"
        )

        // The server queues what each call hands it and the cache hit above never took its
        // answer, so it is dropped before the next request asks for one.
        testState.localServer.cleanup(at: testState.uri)

        let different = try await performCacheRequest(
            testState: testState,
            headers: vary,
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Accept-Language", "en-US")],
            output: "third"
        )

        // Then
        #expect(try responseText(same) == "first")
        #expect(try responseText(different) == "third")
    }

    @Test
    func cache_whenResponseVariesOnEverything_isNotStored() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        _ = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAgeSeconds: 3_600) + [("Vary", "*")],
            cacheStrategy: .returnCachedDataElseLoad
        )
        await testState.dataCache.waitUntilIdle()

        // Then
        #expect(await testState.dataCache.getCachedData(forKey: cacheKey, policy: .all) == nil)
    }

    /// An entry written before `Vary` was recorded cannot be matched to a request, so it is not
    /// served for a response that varies.
    @Test
    func cache_whenStoredResponseVariesButNoRequestWasRecorded_isNotServed() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        let cacheKey = "https://localhost:8888" + testState.uri
        let legacy = await mockCachedData(makeHeaders(maxAgeSeconds: 3_600) + [("Vary", "Accept-Language")])
        await testState.dataCache.setCachedData(legacy, forKey: cacheKey)

        // When
        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAgeSeconds: 3_600),
            cacheStrategy: .returnCachedDataElseLoad,
            output: "network"
        )

        // Then
        #expect(try responseText(response) == "network")
    }

    /// A `Cookie` the caller set by hand (the package turns the cookie jar off) is a credential
    /// like `Authorization`: the response is stored for that cookie, whatever its `Cache-Control`
    /// says besides `max-age`.
    @Test
    func cache_whenRequestHasCookie_servesItToTheSameCookie() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        _ = try await performCacheRequest(
            testState: testState,
            headers: [("Cache-Control", "max-age=1000")],
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Cookie", "session=alice")],
            output: "first"
        )
        await testState.dataCache.waitUntilIdle()

        // When
        let same = try await performCacheRequest(
            testState: testState,
            headers: [("Cache-Control", "max-age=1000")],
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Cookie", "session=alice")],
            output: "second"
        )

        // Then
        #expect(try responseText(same) == "first")
    }

    @Test
    func cache_whenRequestHasCookie_doesNotServeItToAnotherCookie() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        _ = try await performCacheRequest(
            testState: testState,
            headers: [("Cache-Control", "max-age=1000")],
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Cookie", "session=alice")],
            output: "alice"
        )
        await testState.dataCache.waitUntilIdle()

        // When
        let other = try await performCacheRequest(
            testState: testState,
            headers: [("Cache-Control", "max-age=1000")],
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Cookie", "session=bob")],
            output: "bob"
        )

        // Then
        #expect(try responseText(other) == "bob")
    }

    /// A response that varies on `Cookie` records what the request sent for it, and that is a
    /// credential: it goes to the disk as a digest, not as the cookie.
    @Test
    func cache_whenResponseVariesOnACookie_recordsADigestAndNotTheCookie() async throws {
        let testState = try await TestState()
        defer { _ = testState }

        // Given
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        _ = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAgeSeconds: 3_600) + [("Vary", "Cookie, Accept-Language")],
            cacheStrategy: .returnCachedDataElseLoad,
            requestHeaders: [("Cookie", "session=alice-secret"), ("Accept-Language", "pt-BR")]
        )
        await testState.dataCache.waitUntilIdle()

        let recorded = try #require(
            await testState.dataCache.getCachedData(forKey: cacheKey, policy: .all)?
                .cachedResponse.varyRequestHeaders
        )

        // Then: the cookie is a digest, the language is what it was.
        #expect(recorded["cookie"]?.hasPrefix("sha256:") == true)
        #expect(recorded.values.allSatisfy { !$0.contains("alice-secret") })
        #expect(recorded["accept-language"] == "pt-BR")
    }
}

extension CachedRequestTests {

    /// Sleeps past the two second `max-age` used by `makeHeaders`.
    ///
    /// The comparison in `isCachedDataValid` is a strict `<` against `date + maxAge`, so
    /// sleeping exactly two seconds sits right on the boundary. The margin costs nothing and
    /// removes one more reason for these tests to flicker.
    func waitCacheExpiration() async throws {
        let twoSecondsAndAQuarter: UInt64 = 2 * 1_000_000_000 + 250 * 1_000_000
        try await _Concurrency.Task.sleep(nanoseconds: twoSecondsAndAQuarter)
    }

    /// Flips the last byte of the body of the only disk entry in `directoryURL`, leaving its
    /// size alone.
    func flipLastByteOfStoredBody(in directoryURL: URL) throws {
        let entries = try FileManager.default.contentsOfDirectory(atPath: directoryURL.path)
        let record = try #require(entries.first { $0.hasSuffix(".cached") })
        let bodyURL = directoryURL.appendingPathComponent(record).appendingPathComponent("data.record")

        var raw = try Data(contentsOf: bodyURL)
        raw[raw.count - 1] ^= 0xFF
        try raw.write(to: bodyURL)
    }

    func mockCachedData(
        _ headers: [(String, String)] = [],
        contentLengthOverride: Int? = nil,
        includeContentLength: Bool = true,
        policy: DataCache.Policy.Set = .all,
        body: Data? = nil
    ) async -> CachedData {
        let data = body ?? (try? JSONEncoder().encode(["receivedBytes": "0"]))

        var responseHeaders = headers
        if includeContentLength {
            responseHeaders.append(("Content-Length", String(contentLengthOverride ?? data?.count ?? .zero)))
        }

        return await CachedData(
            response: ResponseHead(
                url: URL(string: "https://localhost:8888"),
                status: .init(code: 200, reason: "Ok"),
                version: .init(minor: 1, major: 2),
                headers: HTTPHeaders(responseHeaders),
                isKeepAlive: false
            ),
            policy: policy,
            data: data ?? Data()
        )
    }

    private func makeHeaders(
        eTag: UUID? = nil,
        noCache: Bool = false,
        maxAge: Bool = true,
        maxAgeSeconds: Int = 2,
        expiresOffsetSeconds: Double = 2
    ) -> [(String, String)] {
        if noCache {
            return [("Cache-Control", "no-cache")]
        }

        var headers = [(String, String)]()

        if let eTag {
            headers.append(("ETag", String(describing: eTag)))
        }

        let now = Date()

        if maxAge {
            // A separate parameter from `expiresOffsetSeconds`, but both exist for the same
            // reason: the "still valid" tests need a window wide enough to outlast the actual
            // request/response round trip (TLS handshake to the local server, cache lookup, and
            // everything in between) on a loaded CI simulator, not just the fixed two seconds
            // `waitCacheExpiration()` sleeps past for the "already expired" ones, which is what
            // the default here still matches.
            headers.append(("Cache-Control", "public, max-age=\(maxAgeSeconds)"))
        } else {
            let date = now.addingTimeInterval(expiresOffsetSeconds)

            headers.append(("Cache-Control", "public"))
            headers.append(("Expires", date.toHTTPDateString()))
        }

        return headers
    }

    /// A monitor hears what a response served from the cache measured too: no executor is there to
    /// tell it, so it is told from where the cache answered.
    @Test
    func cache_whenServedFromTheCache_aMonitorHearsTheCacheTransaction() async throws {
        // Given
        let testState = try await TestState()
        let cacheKey = "https://localhost:8888" + testState.uri
        let monitor = RecordingMonitor()

        await testState.dataCache.setCachedData(
            await mockCachedData(makeHeaders(maxAgeSeconds: 3_600)),
            forKey: cacheKey
        )

        // When
        _ = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(maxAgeSeconds: 3_600),
            cacheStrategy: .returnCachedDataElseLoad,
            monitor: monitor
        )

        // Then
        try await eventually(timeout: 30) { monitor.transactions.count == 1 && monitor.hasEnded }

        #expect(monitor.transactions.map(\.source) == [.cache])
        #expect(monitor.states() == ["started", "finished"])
    }

    @Test
    func cache_whenRevalidationConfirmsTheCache_aMonitorHearsTheRevalidationThenTheCache() async throws {
        // Given
        let testState = try await TestState()
        let eTag = UUID()
        let cacheKey = "https://localhost:8888" + testState.uri
        let monitor = RecordingMonitor()

        await testState.dataCache.setCachedData(
            await mockCachedData(makeHeaders(eTag: eTag, maxAgeSeconds: 3_600)),
            forKey: cacheKey
        )

        // When
        _ = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: eTag, maxAgeSeconds: 3_600),
            cacheStrategy: .reloadAndValidateCachedData,
            monitor: monitor
        )

        // Then
        try await eventually(timeout: 30) { monitor.transactions.count == 2 && monitor.hasEnded }

        #expect(monitor.transactions.map(\.source) == [.revalidation, .cache])
        #expect(monitor.states() == ["started", "finished"])
    }

    /// The revalidation is told as soon as it is over, ahead of the request that follows it.
    @Test
    func cache_whenRevalidationFindsTheCacheInvalid_aMonitorHearsTheRevalidationThenTheRequest() async throws {
        // Given
        let testState = try await TestState()
        let eTag = UUID()
        let cacheKey = "https://localhost:8888" + testState.uri
        let monitor = RecordingMonitor()

        await testState.dataCache.setCachedData(
            await mockCachedData(makeHeaders()),
            forKey: cacheKey
        )

        try await waitCacheExpiration()

        // When
        _ = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: eTag),
            cacheStrategy: .reloadAndValidateCachedData,
            monitor: monitor
        )

        // Then
        try await eventually(timeout: 30) { monitor.transactions.count == 2 && monitor.hasEnded }

        #expect(monitor.transactions.map(\.source) == [.revalidation, .network])
        #expect(monitor.states() == ["started", "finished"])
    }

    /// What the server put in `response` of the body, whether it came off the network or out of
    /// the cache.
    func responseText(_ result: TaskResult<Data>) throws -> String {
        try JSONDecoder().decode(HTTPResult<String>.self, from: result.payload).response
    }

    func performCacheRequest(
        testState: TestState,
        headers: [(String, String)],
        status: LocalServer.ResponseConfiguration.Status = .ok,
        cachePolicy: DataCache.Policy.Set = .all,
        cacheStrategy: CacheStrategy,
        memoryCapacity: Int64 = .zero,
        diskCapacity: Int64 = .zero,
        encryptionKey: DataCache.EncryptionKey? = nil,
        cacheHeader: CacheHeader? = nil,
        includesAuthorizationHeader: Bool = false,
        requestHeaders: [(String, String)] = [],
        output: String? = nil,
        executor: Session.Executor? = nil,
        logger: Logger? = nil,
        monitor: RecordingMonitor? = nil
    ) async throws -> TaskResult<Data> {
        let response = try responseConfiguration(headers, output ?? testState.output, status: status)

        testState.localServer.insert(response, at: testState.uri)

        var base = Session.localServer

        if let executor {
            base = base.requiredExecutor(executor)
        }

        let session =
            base
            .cachePolicy(cachePolicy)
            .cacheStrategy(cacheStrategy)
            .cache(
                memoryCapacity: memoryCapacity,
                diskCapacity: diskCapacity,
                url: testState.dataCache.directoryURL,
                encryptionKey: encryptionKey
            )

        let task = DataTask {
            session

            SecureConnection {
                TrustRoots {
                    RequestDL.Certificate(testState.certificate.certificateURL.absolutePath(percentEncoded: false))
                }
            }

            BaseURL(testState.localServer.baseURL)
            Path(testState.uri)

            if let cacheHeader {
                cacheHeader
            }

            if includesAuthorizationHeader {
                RequestDL.Authorization(.bearer, token: "test-token")
            }

            PropertyForEach(requestHeaders, id: \.0) {
                CustomHeader(name: $0.0, value: $0.1)
            }
        }
        .environment(\.logger, logger)

        guard let monitor else {
            return try await task.result()
        }

        return try await task.monitor(monitor).result()
    }

    private func responseConfiguration(
        _ headers: [(String, String)],
        _ output: String,
        status: LocalServer.ResponseConfiguration.Status = .ok
    ) throws -> LocalServer.ResponseConfiguration {
        LocalServer.ResponseConfiguration(
            status: status,
            headers: .init(headers),
            data: try JSONEncoder().encode(output)
        )
    }
}
