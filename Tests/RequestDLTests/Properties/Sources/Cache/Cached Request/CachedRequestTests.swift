/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class CachedRequestTests: XCTestCase {

    private let certificate = Certificates().server()
    private let dataCache = DataCache.shared
    private let output = String.randomString(length: 64)
    private var localServer: LocalServer?

    override func setUp() async throws {
        try await super.setUp()

        dataCache.removeAll()
        dataCache.memoryCapacity = 8 * 1_024 * 1_024
        dataCache.diskCapacity = 64 * 1_024 * 1_024

        localServer = try await LocalServer(.standard)
        localServer?.cleanup()
    }

    override func tearDown() async throws {
        try await super.tearDown()

        dataCache.removeAll()
        dataCache.memoryCapacity = .zero
        dataCache.diskCapacity = .zero

        localServer?.cleanup()
        localServer = nil
    }

    func testCache_whenNoCacheOnIgnoresCachedDataStrategy() async throws {
        // Given
        let cacheKey = "https://localhost:8888"

        // When
        let response = try await performCacheRequest(
            headers: makeHeaders(noCache: true),
            cacheStrategy: .ignoreCachedData
        )

        let cachedData = DataCache.shared.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        XCTAssertNil(cachedData)
        XCTAssertEqual(response.head.headers.first(name: "Cache-Control"), "no-cache")
    }

    func testCache_whenNoCacheOnIgnoresCachedDataStrategyWithPreviousCache() async throws {
        // Given
        let cacheData = mockCachedData(makeHeaders(eTag: UUID()))
        let cacheKey = "https://localhost:8888"

        // When
        dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            headers: makeHeaders(noCache: true),
            cacheStrategy: .ignoreCachedData
        )

        let updatedCachedData = DataCache.shared.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        XCTAssertEqual(updatedCachedData?.response, cacheData.response)
        XCTAssertEqual(response.head.headers.first(name: "Cache-Control"), "no-cache")
    }

    func testCache_whenUseCachedDataOnlyStrategyWithoutCache() async throws {
        // Given
        var thrownError: Error?

        // When
        do {
            _ = try await performCacheRequest(
                headers: makeHeaders(),
                cacheStrategy: .useCachedDataOnly
            )
        } catch {
            thrownError = error
        }

        // Then
        XCTAssertTrue(thrownError is EmptyCachedDataError)
    }

    func testCache_whenUseCachedDataOnlyStrategyWithValidCacheMaxAge() async throws {
        let cacheData = mockCachedData(makeHeaders())
        let cacheKey = "https://localhost:8888"

        // When
        dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            headers: makeHeaders(eTag: UUID()),
            cacheStrategy: .useCachedDataOnly
        )

        let updatedCachedData = dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        XCTAssertEqual(updatedCachedData?.response, cacheData.response)
        XCTAssertEqual(response.head, cacheData.response)
    }

    func testCache_whenUseCachedDataOnlyStrategyWithInvalidCacheMaxAge() async throws {
        let cacheData = mockCachedData(makeHeaders())
        let cacheKey = "https://localhost:8888"
        var thrownError: Error?

        // When
        dataCache.setCachedData(cacheData, forKey: cacheKey)

        try await waitCacheExpiration()

        do {
            _ = try await performCacheRequest(
                headers: makeHeaders(),
                cacheStrategy: .useCachedDataOnly
            )
        } catch {
            thrownError = error
        }

        // Then
        XCTAssertTrue(thrownError is EmptyCachedDataError)
    }

    func testCache_whenUseCachedDataOnlyStrategyWithValidCacheExpires() async throws {
        let cacheData = mockCachedData(makeHeaders(maxAge: false))
        let cacheKey = "https://localhost:8888"

        // When
        dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            headers: makeHeaders(eTag: UUID()),
            cacheStrategy: .useCachedDataOnly
        )

        let updatedCachedData = dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        XCTAssertEqual(updatedCachedData?.response, cacheData.response)
        XCTAssertEqual(response.head, cacheData.response)
    }

    func testCache_whenUseCachedDataOnlyStrategyWithInvalidCacheExpires() async throws {
        let cacheData = mockCachedData(makeHeaders(maxAge: false))
        let cacheKey = "https://localhost:8888"
        var thrownError: Error?

        // When
        dataCache.setCachedData(cacheData, forKey: cacheKey)

        try await waitCacheExpiration()

        do {
            _ = try await performCacheRequest(
                headers: makeHeaders(),
                cacheStrategy: .useCachedDataOnly
            )
        } catch {
            thrownError = error
        }

        // Then
        XCTAssertTrue(thrownError is EmptyCachedDataError)
    }

    func testCache_whenReturnCachedDataElseLoadWithValidCache() async throws {
        let cacheData = mockCachedData(makeHeaders())
        let cacheKey = "https://localhost:8888"

        // When
        dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            headers: makeHeaders(eTag: UUID()),
            cacheStrategy: .returnCachedDataElseLoad
        )

        let updatedCachedData = dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        XCTAssertEqual(updatedCachedData?.response, cacheData.response)
        XCTAssertEqual(response.head, cacheData.response)
    }

    func testCache_whenReturnCachedDataElseLoadWithInvalidCache() async throws {
        let cacheData = mockCachedData(makeHeaders())
        let cacheKey = "https://localhost:8888"

        // When
        dataCache.setCachedData(cacheData, forKey: cacheKey)

        try await waitCacheExpiration()

        let response = try await performCacheRequest(
            headers: makeHeaders(),
            cacheStrategy: .returnCachedDataElseLoad
        )

        let updatedCachedData = dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        XCTAssertNotEqual(updatedCachedData?.response, cacheData.response)
        XCTAssertNotEqual(response.head, cacheData.response)
    }

    func testCache_whenReloadAndValidateCachedDataWithValidCache() async throws {
        let eTag = UUID()
        let cacheData = mockCachedData(makeHeaders(eTag: eTag))
        let cacheKey = "https://localhost:8888"

        // When
        dataCache.setCachedData(cacheData, forKey: cacheKey)

        let response = try await performCacheRequest(
            headers: makeHeaders(eTag: eTag),
            cacheStrategy: .reloadAndValidateCachedData
        )

        let updatedCachedData = dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        XCTAssertEqual(updatedCachedData?.response, cacheData.response)
        XCTAssertEqual(response.head, cacheData.response)
    }

    func testCache_whenReloadAndValidateCachedDataWithInvalidCache() async throws {
        let eTag = UUID()
        let cacheData = mockCachedData(makeHeaders())
        let cacheKey = "https://localhost:8888"

        // When
        dataCache.setCachedData(cacheData, forKey: cacheKey)

        try await waitCacheExpiration()

        let response = try await performCacheRequest(
            headers: makeHeaders(eTag: eTag),
            cacheStrategy: .reloadAndValidateCachedData
        )

        let updatedCachedData = dataCache.getCachedData(
            forKey: cacheKey,
            policy: .all
        )

        // Then
        XCTAssertNotEqual(updatedCachedData?.response, cacheData.response)
        XCTAssertNotEqual(response.head, cacheData.response)
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
        headers: [(String, String)],
        cachePolicy: DataCache.Policy.Set = .all,
        cacheStrategy: CacheStrategy
    ) async throws -> TaskResult<Data> {
        let localServer = try XCTUnwrap(localServer)
        let response = try responseConfiguration(headers, output)

        localServer.insert(response)

        let output = try await DataTask {
            SecureConnection {
                #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
                DefaultTrusts()
                AdditionalTrusts {
                    RequestDL.Certificate(certificate.certificateURL.absolutePath(percentEncoded: false))
                }
                #else
                Trusts {
                    RequestDL.Certificate(certificate.certificateURL.absolutePath(percentEncoded: false))
                }
                #endif
            }

            BaseURL(localServer.baseURL)
                .cachePolicy(cachePolicy)
                .cacheStrategy(cacheStrategy)
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
