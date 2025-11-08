/*
 See LICENSE for this package's licensing information.
*/

import Foundation
import Testing
@testable import RequestDL

@Suite(.localDataCache(.autogenerate), .serialized)
struct CachedRequestTests {

    final class TestState: Sendable {

        let certificate = Certificates().server()
        let dataCache = DataCache.shared
        let output = String.randomString(length: 64)
        let localServer: LocalServer
        let uri: String

        init() async throws {
            uri = "/" + UUID().uuidString
            localServer = try await LocalServer(.standard)
            localServer.cleanup(at: uri)

            dataCache.removeAll()
            dataCache.memoryCapacity = 8 * 1_024 * 1_024
            dataCache.diskCapacity = 64 * 1_024 * 1_024
        }

        deinit {
            dataCache.removeAll()
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

        let cachedData = DataCache.shared.getCachedData(
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
        let cacheData = mockCachedData(makeHeaders(eTag: UUID()))
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(noCache: true),
            cacheStrategy: .ignoreCachedData
        )

        let updatedCachedData = DataCache.shared.getCachedData(
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
        let cacheData = mockCachedData(makeHeaders())
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: UUID()),
            cacheStrategy: .useCachedDataOnly
        )

        let updatedCachedData = testState.dataCache.getCachedData(
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
        let cacheData = mockCachedData(makeHeaders())
        let cacheKey = "https://localhost:8888" + testState.uri
        var thrownError: Error?

        // When
        testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

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
        let cacheData = mockCachedData(makeHeaders(maxAge: false))
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: UUID()),
            cacheStrategy: .useCachedDataOnly
        )

        let updatedCachedData = testState.dataCache.getCachedData(
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
        let cacheData = mockCachedData(makeHeaders(maxAge: false))
        let cacheKey = "https://localhost:8888" + testState.uri
        var thrownError: Error?

        // When
        testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

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
        let cacheData = mockCachedData(makeHeaders())
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: UUID()),
            cacheStrategy: .returnCachedDataElseLoad
        )

        let updatedCachedData = testState.dataCache.getCachedData(
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
        let cacheData = mockCachedData(makeHeaders())
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        try await waitCacheExpiration()

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(),
            cacheStrategy: .returnCachedDataElseLoad
        )

        let updatedCachedData = testState.dataCache.getCachedData(
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
        let cacheData = mockCachedData(makeHeaders(eTag: eTag))
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: eTag),
            cacheStrategy: .reloadAndValidateCachedData
        )

        let updatedCachedData = testState.dataCache.getCachedData(
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
        let cacheData = mockCachedData(makeHeaders())
        let cacheKey = "https://localhost:8888" + testState.uri

        // When
        testState.dataCache.setCachedData(cacheData, forKey: cacheKey)

        try await waitCacheExpiration()

        let response = try await performCacheRequest(
            testState: testState,
            headers: makeHeaders(eTag: eTag),
            cacheStrategy: .reloadAndValidateCachedData
        )

        let updatedCachedData = testState.dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        #expect(updatedCachedData?.response != cacheData.response)
        #expect(response.head != cacheData.response)
    }
}

extension CachedRequestTests {

    func waitCacheExpiration() async throws {
        try await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)
    }

    func mockCachedData(_ headers: [(String, String)] = []) -> CachedData {
        let data = try? JSONSerialization.data(withJSONObject: [
            "receivedBytes": "0"
        ])

        return CachedData(
            response: ResponseHead(
                url: URL(string: "https://localhost:8888"),
                status: .init(code: 200, reason: "Ok"),
                version: .init(minor: 1, major: 2),
                headers: HTTPHeaders(headers + [
                    ("Content-Length", String(data?.count ?? .zero))
                ]),
                isKeepAlive: false
            ),
            policy: .all,
            data: data ?? Data()
        )
    }

    private func makeHeaders(
        eTag: UUID? = nil,
        noCache: Bool = false,
        maxAge: Bool = true
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
            let date = now.addingTimeInterval(TimeInterval(maxAgeSeconds))

            let dateFormatter = DateFormatter()
            dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            dateFormatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
            dateFormatter.timeZone = TimeZone(identifier: "GMT")
            headers.append(("Cache-Control", "public"))
            headers.append(("Expires", dateFormatter.string(from: date)))
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
            Session()
                .disableNetworkFramework()
                .cachePolicy(cachePolicy)
                .cacheStrategy(cacheStrategy)
                .cache(url: testState.dataCache.directoryURL)

            SecureConnection {
                Trusts {
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
            data: try JSONSerialization.data(
                withJSONObject: output,
                options: [.fragmentsAllowed]
            )
        )
    }
}
