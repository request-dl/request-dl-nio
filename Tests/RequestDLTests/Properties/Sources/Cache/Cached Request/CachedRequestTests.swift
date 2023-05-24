/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

class CachedRequestTests: XCTestCase {

    private let certificate = Certificates().server()
    private let dataCache = DataCache.shared
    private let output = String.randomString(length: 1_024)
    private var localServer: LocalServer!

    override func setUp() async throws {
        try await super.setUp()
        dataCache.removeAll()
        localServer = try await LocalServer(.standard)
    }

    override func tearDown() async throws {
        try await super.tearDown()
        dataCache.removeAll()
        localServer = nil
    }

    func testCache_whenServerNoCacheOnIgnoresCachedDataStrategy() async throws {
        try await performCacheRequest(
            headers: makeHeaders(noCache: true),
            cacheStrategy: .ignoreCachedData,
            body: { baseURL, response in
                // When
                let cachedData = DataCache.shared.getCachedData(forKey: baseURL, policy: .all)

                // Then
                XCTAssertEqual(response.head.headers.first(name: "Cache-Control"), "no-cache")
                XCTAssertNil(cachedData)
            }
        )
    }

    func testCache_whenServerCacheOnIgnoresCachedDataStrategy() async throws {
        try await performCacheRequest(
            headers: makeHeaders(),
            cacheStrategy: .ignoreCachedData,
            body: { baseURL, response in
                // When
                let cachedData = DataCache.shared.getCachedData(forKey: baseURL, policy: .all)

                // Then
                XCTAssertEqual(response.head.headers.first(name: "Cache-Control"), "public, max-age=5")
                XCTAssertNil(cachedData)
            }
        )
    }

    func testCache_whenServerCacheOnUseCachedDataOnlyStrategyWithoutCache() async throws {
        do {
            try await performCacheRequest(
                headers: makeHeaders(),
                cacheStrategy: .useCachedDataOnly,
                body: { baseURL, response in
                    // When
                    let cachedData = DataCache.shared.getCachedData(forKey: baseURL, policy: .all)

                    // Then
                    XCTAssertEqual(response.head.headers.first(name: "Cache-Control"), "public, max-age=15")
                    XCTAssertNil(cachedData)
                }
            )

            XCTFail("No error was thrown")
        } catch {
            XCTAssertTrue(error is EmptyCachedDataError)
        }
    }

    func testCache_whenServerCacheOnUseCachedDataOnlyStrategyWithValidCache() async throws {
        // Given
        let eTag = UUID()
        let cachedData = SendableBox(CachedData?.none)

        try await performCacheRequest(
            headers: makeHeaders(eTag: eTag),
            cacheStrategy: .reloadAndValidateCachedData,
            body: { baseURL, response in
                try await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)

                cachedData(
                    self.dataCache.getCachedData(
                        forKey: "https://\(baseURL)",
                        policy: .all
                    )
                )
            }
        )

        // When
        try await performCacheRequest(
            headers: makeHeaders(eTag: eTag),
            cacheStrategy: .useCachedDataOnly,
            body: { baseURL, response in
                // Then
                XCTAssertEqual(cachedData()?.response, response.head)
            }
        )
    }

    func testCache_whenServerCacheOnUseCachedDataOnlyStrategyWithInvalidCache() async throws {
        // Given
        let eTag = UUID()

        try await performCacheRequest(
            headers: makeHeaders(eTag: eTag),
            cacheStrategy: .reloadAndValidateCachedData,
            body: { baseURL, response in }
        )

        // When
        try await _Concurrency.Task.sleep(nanoseconds: 5_000_000_000)

        // Then
        do {
            try await performCacheRequest(
                headers: makeHeaders(eTag: eTag),
                cacheStrategy: .useCachedDataOnly,
                body: { baseURL, response in }
            )

            XCTFail("No error was thrown")
        } catch {
            XCTAssertTrue(error is EmptyCachedDataError)
        }
    }
}

extension CachedRequestTests {

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
        let maxAgeSeconds = 5

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
        cacheStrategy: CacheStrategy,
        body: @escaping @Sendable (String, TaskResult<Data>) async throws -> Void
    ) async throws {
        let response = LocalServer.ResponseConfiguration(
            headers: .init(headers),
            data: try JSONSerialization.data(
                withJSONObject: output,
                options: [.fragmentsAllowed]
            )
        )

        await localServer.register(response)
        defer { localServer.releaseConfiguration() }

        let baseURL = localServer.baseURL

        let output = try await DataTask {
            SecureConnection {
                Trusts {
                    RequestDL.Certificate(certificate.certificateURL.absolutePath(percentEncoded: false))
                }
            }

            BaseURL(baseURL)
                .cachePolicy(cachePolicy)
                .cacheStrategy(cacheStrategy)
        }
        .result()

        try await body(baseURL, output)
    }
}
