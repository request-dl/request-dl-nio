//
// See LICENSE for this package's licensing information.
//

import NIOCore
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
import struct Foundation.URL
import struct Foundation.Date
import class Foundation.JSONEncoder
#endif

@Suite(.serialized)
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
        let cacheData = await mockCachedData(makeHeaders())
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

    @Test
    func cache_whenUseCachedDataOnlyStrategyWithValidCacheExpires() async throws {
        let testState = try await TestState()
        // A wide `Expires` window, not the two seconds `cache_whenUseCachedDataOnlyStrategyWithInvalidCacheExpires`
        // waits past. This test never sleeps, so its window only has to outlast the actual
        // request/response round trip below — on a loaded CI simulator that alone can exceed a
        // couple of seconds, which was flaking this test even though the cache itself was still
        // perfectly valid.
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
        let cacheData = await mockCachedData(makeHeaders())
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
        let cacheData = await mockCachedData(makeHeaders(eTag: eTag))
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        await testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

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
}

extension CachedRequestTests {

    /// Sleeps past the two second `max-age` used by `makeHeaders`.
    ///
    /// The comparison in `isCachedDataValid` is a strict `<` against `date + maxAge`, so
    /// sleeping exactly two seconds sits right on the boundary. The margin costs nothing and
    /// removes one more reason for these tests to flicker.
    func waitCacheExpiration() async throws {
        try await _Concurrency.Task
            .sleep(nanoseconds: UInt64((TimeAmount.seconds(2) + .milliseconds(250)).nanoseconds))
    }

    func mockCachedData(_ headers: [(String, String)] = []) async -> CachedData {
        let data = try? JSONEncoder().encode(["receivedBytes": "0"])

        return await CachedData(
            response: ResponseHead(
                url: URL(string: "https://localhost:8888"),
                status: .init(code: 200, reason: "Ok"),
                version: .init(minor: 1, major: 2),
                headers: HTTPHeaders(
                    headers + [
                        ("Content-Length", String(data?.count ?? .zero))
                    ]
                ),
                isKeepAlive: false
            ),
            policy: .all,
            data: data ?? Data()
        )
    }

    private func makeHeaders(
        eTag: UUID? = nil,
        noCache: Bool = false,
        maxAge: Bool = true,
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
        let maxAgeSeconds = 2

        if maxAge {
            headers.append(("Cache-Control", "public, max-age=\(maxAgeSeconds)"))
        } else {
            // A separate offset from `maxAgeSeconds`: the "still valid" `Expires` tests need a
            // window wide enough to outlast the actual request/response round trip (TLS
            // handshake to the local server, cache lookup, and everything in between), not just
            // the fixed two seconds `waitCacheExpiration()` sleeps past for the "already
            // expired" ones.
            let date = now.addingTimeInterval(expiresOffsetSeconds)

            headers.append(("Cache-Control", "public"))
            headers.append(("Expires", date.toHTTPDateString()))
        }

        return headers
    }

    func performCacheRequest(
        testState: TestState,
        headers: [(String, String)],
        cachePolicy: DataCache.Policy.Set = .all,
        cacheStrategy: CacheStrategy
    ) async throws -> TaskResult<Data> {
        let response = try responseConfiguration(headers, testState.output)

        testState.localServer.insert(response, at: testState.uri)

        let output = try await DataTask {
            Session.localServer
                .cachePolicy(cachePolicy)
                .cacheStrategy(cacheStrategy)
                .cache(url: testState.dataCache.directoryURL)

            SecureConnection {
                TrustRoots {
                    RequestDL.Certificate(testState.certificate.certificateURL.absolutePath(percentEncoded: false))
                }
            }

            BaseURL(testState.localServer.baseURL)
            Path(testState.uri)
        }
        .result()

        return output
    }

    private func responseConfiguration(
        _ headers: [(String, String)],
        _ output: String
    ) throws -> LocalServer.ResponseConfiguration {
        LocalServer.ResponseConfiguration(
            headers: .init(headers),
            data: try JSONEncoder().encode(output)
        )
    }
}
