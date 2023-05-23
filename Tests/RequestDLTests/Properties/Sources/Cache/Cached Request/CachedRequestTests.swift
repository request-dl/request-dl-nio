/*
 See LICENSE for this package's licensing information.
*/

import XCTest
@testable import RequestDL

extension String {

    static func randomString(length: Int) -> String {
        let lowercaseCharacters = "abcdefghijklmnopqrstuvwxyz"
        let uppercaseCharacters = lowercaseCharacters.uppercased()
        let decimalCharacters = "0123456789"

        let characters = [
            lowercaseCharacters,
            uppercaseCharacters,
            decimalCharacters
        ].joined()

        var string = ""

        for _ in 0 ..< length {
            string += String(characters.randomElement()!)
        }

        return string
    }
}

class CachedRequestTests: XCTestCase {

    private let certificate = Certificates().server()
    private let dataCache = DataCache.shared
    private let output = String.randomString(length: 1_024)

    override func setUp() async throws {
        try await super.setUp()
        dataCache.removeAll()
    }

    func testCache_whenServerNoCacheOnIgnoresCachedDataStrategy() async throws {
        try await performCacheRequest(
            noCache: true,
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
            noCache: false,
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
                noCache: false,
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
        let cachedData = SendableBox(CachedData?.none)

        try await performCacheRequest(
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
            cacheStrategy: .useCachedDataOnly,
            body: { baseURL, response in
                // Then
                XCTAssertEqual(cachedData()?.response, response.head)
            }
        )
    }

    func testCache_whenServerCacheOnUseCachedDataOnlyStrategyWithInvalidCache() async throws {
        // Given
        try await performCacheRequest(
            port: 8080,
            cacheStrategy: .reloadAndValidateCachedData,
            body: { baseURL, response in }
        )

        // When
        try await _Concurrency.Task.sleep(nanoseconds: 5_000_000_000)

        // Then
        do {
            try await performCacheRequest(
                port: 8080,
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

    func performCacheRequest(
        port: UInt = 8888,
        noCache: Bool = false,
        maxAge: Bool = true,
        cachePolicy: DataCache.Policy.Set = .all,
        cacheStrategy: CacheStrategy,
        body: @escaping @Sendable (String, TaskResult<Data>) async throws -> Void
    ) async throws {
        try await withServer(port: port, noCache: noCache, maxAge: maxAge) { baseURL in
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

    func withServer(
        port: UInt,
        noCache: Bool = false,
        maxAge: Bool = true,
        _ closure: @Sendable (String) async throws -> Void
    ) async throws {
        try await InternalServer(
            host: "localhost",
            port: port,
            response: output,
            noCache: noCache,
            maxAge: maxAge
        ).run(closure)
    }
}
