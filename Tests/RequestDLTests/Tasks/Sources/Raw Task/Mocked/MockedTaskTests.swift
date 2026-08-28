//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncTesting
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.URL
import struct Foundation.UUID
import class Foundation.JSONEncoder
#endif

@Suite(.concurrent(2), .nonFatalWatchdog)
struct MockedTaskTests {

    @Test
    func mock_whenHeadersAndData() async throws {
        // Given
        let statusCode: UInt = 200
        let data = Data("Hello World".utf8)

        // When
        // The mocked response mirrors every header the resolved request would carry.
        let result = try await MockedTask(
            status: .init(code: statusCode, reason: "Ok"),
            content: {
                BaseURL("localhost")
                AcceptHeader(.json)
                Payload(data: data, contentType: .text)
            }
        )
        .collectData()
        .result()

        // Then
        let response = result.head

        #expect(response.status.code == statusCode)
        #expect(result.payload == data)

        #expect(response.url?.absoluteString == "https://localhost")
        #expect(
            response.headers
                == .init([
                    ("Accept", "application/json"),
                    ("Content-Type", "text/plain"),
                    ("Content-Length", String(data.count)),
                ])
        )
    }

    @Test
    func mock_whenHeadersOverlaysOnTopOfMirroredRequest() async throws {
        // Given
        let data = Data("Hello World".utf8)

        // When
        // `headers` overlays on top of the mirrored request headers: it overrides a name already
        // there (`Content-Type`) and adds one that is not part of the request at all.
        let result = try await MockedTask(
            headers: [
                "Content-Type": "application/json",
                "X-Mock-Only": "true",
            ],
            content: {
                BaseURL("localhost")
                AcceptHeader(.json)
                Payload(data: data, contentType: .text)
            }
        )
        .collectData()
        .result()

        // Then
        let response = result.head
        #expect(response.headers.first(name: "Content-Type") == "application/json")
        #expect(response.headers.first(name: "Content-Length") == String(data.count))
        #expect(response.headers.first(name: "Accept") == "application/json")
        #expect(response.headers.first(name: "X-Mock-Only") == "true")
    }

    @Test
    func mock_whenDefaultValues() async throws {
        // Given
        let data = Data("Hello World".utf8)

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
            Payload(data: data)
        }
        .collectData()
        .result()

        // Then
        let head = result.head

        #expect(head.status.code == 200)
        #expect(result.payload == data)
        #expect(
            head.headers
                == .init([
                    ("Content-Type", "application/octet-stream"),
                    ("Content-Length", String(data.count)),
                ])
        )
    }

    @Test
    func mock_whenUseCachedDataOnlyStrategyWithNoCache_stillSucceedsBecauseItIsRemapped() async throws {
        // Given
        let data = Data("Hello World".utf8)

        // When
        // A mocked task always resolves regardless of the declared cache strategy — internally
        // remapped away from `.useCachedDataOnly` before `CacheControl` ever runs, since a mock
        // has no real cache to serve and `.useCachedDataOnly` would otherwise always throw
        // `EmptyCachedDataError`.
        let result = try await MockedTask {
            BaseURL("localhost")
            Path(UUID().uuidString)
            Session.localServer.cacheStrategy(.useCachedDataOnly)
            Payload(data: data)
        }
        .collectData()
        .result()

        // Then
        #expect(result.payload == data)
    }

    @Test
    func mock_whenValidCacheExists_returnsCachedDataInsteadOfMockedContent() async throws {
        // Given
        let uniqueKey = UUID().uuidString
        let dataCache = DataCache(suiteName: uniqueKey)
        defer {
            dataCache.memoryCapacity = .zero
            dataCache.diskCapacity = .zero
        }

        await dataCache.removeAll()
        dataCache.memoryCapacity = 8 * 1_024 * 1_024
        dataCache.diskCapacity = 64 * 1_024 * 1_024

        let path = UUID().uuidString
        let cacheKey = "https://localhost/\(path)"
        let cachedPayload = try JSONEncoder().encode(["cached": true])

        let cachedData = await CachedData(
            response: ResponseHead(
                url: URL(string: cacheKey),
                status: .init(code: 200, reason: "Ok"),
                version: .init(minor: 0, major: 2),
                headers: .init([
                    ("Cache-Control", "public, max-age=3600"),
                    ("Content-Length", String(cachedPayload.count)),
                ]),
                isKeepAlive: false
            ),
            policy: .all,
            data: cachedPayload
        )

        await dataCache.setCachedData(cachedData, forKey: cacheKey)

        // When
        // Deliberately no `Payload` here: `RequestConfiguration.isCacheEnabled` requires a
        // `nil` body, and a mocked task mirrors `Payload` into the response body through the
        // same mechanism a real request would use for its upload body — so setting one would
        // disable caching altogether and never reach `CacheControl`'s cache-hit path.
        let result = try await MockedTask {
            BaseURL("localhost")
            Path(path)
            Session.localServer
                .cachePolicy(.all)
                .cacheStrategy(.returnCachedDataElseLoad)
                .cache(url: dataCache.directoryURL)
        }
        .collectData()
        .result()

        // Then
        #expect(result.payload == cachedPayload)
    }

    @Test
    func mock_whenCachingEnabled_writesMockedResponseToCache() async throws {
        // Given
        let uniqueKey = UUID().uuidString
        let dataCache = DataCache(suiteName: uniqueKey)
        defer {
            dataCache.memoryCapacity = .zero
            dataCache.diskCapacity = .zero
        }

        await dataCache.removeAll()
        dataCache.memoryCapacity = 8 * 1_024 * 1_024
        dataCache.diskCapacity = 64 * 1_024 * 1_024

        let path = UUID().uuidString
        let cacheKey = "https://localhost/\(path)"

        // When
        // No `Payload` here either — see the comment in the cache-hit test above; the mocked
        // response body ends up empty (`mockRequest`'s `else { downloadBuffer.close() }`
        // branch), but that is enough to prove the write side (`cacheStream`) ran, which is
        // what this test targets.
        _ = try await MockedTask {
            BaseURL("localhost")
            Path(path)
            Session.localServer
                .cachePolicy(.all)
                .cache(url: dataCache.directoryURL)
        }
        .collectData()
        .result()

        await dataCache.waitUntilIdle()

        // Then
        let cachedData = await dataCache.getCachedData(forKey: cacheKey, policy: .all)
        #expect(cachedData != nil)
    }

    @Test
    func mock_whenMethodIsSet_addsRequestMethodHeaderToMockedResponse() async throws {
        // Given
        let data = Data("Hello World".utf8)

        // When
        let result = try await MockedTask {
            BaseURL("localhost")
            RequestMethod(.post)
            Payload(data: data)
        }
        .collectData()
        .result()

        // Then
        #expect(result.head.headers.first(name: "rdl-request-method") == "POST")
    }

    @Test
    func mock_whenThrowing_throwsErrorInsteadOfReturningResponse() async throws {
        // Given
        struct SimulatedTransportError: Error, Equatable {}

        // When
        do {
            _ = try await MockedTask(throwing: SimulatedTransportError())
                .collectData()
                .result()
            Issue.record("Expected MockedTask(throwing:) to throw")
        } catch let error as SimulatedTransportError {
            // Then
            #expect(error == SimulatedTransportError())
        }
    }

    @available(iOS 16, tvOS 16, watchOS 9, macOS 13, *)
    @Test
    func mock_whenDelay_waitsBeforeDeliveringResponse() async throws {
        // Given
        let clock = ContinuousClock()
        let delay = UnitTime.milliseconds(200)

        // When
        let start = clock.now
        _ = try await MockedTask(delay: delay) {
            BaseURL("localhost")
        }
        .collectData()
        .result()
        let elapsed = clock.now - start

        // Then
        #expect(elapsed >= .nanoseconds(delay.nanoseconds))
    }

    @available(iOS 16, tvOS 16, watchOS 9, macOS 13, *)
    @Test
    func mock_whenThrowingWithDelay_waitsBeforeThrowing() async throws {
        // Given
        struct SimulatedTransportError: Error {}
        let clock = ContinuousClock()
        let delay = UnitTime.milliseconds(200)

        // When
        let start = clock.now
        await #expect(throws: SimulatedTransportError.self) {
            try await MockedTask(throwing: SimulatedTransportError(), delay: delay)
                .collectData()
                .result()
        }
        let elapsed = clock.now - start

        // Then
        #expect(elapsed >= .nanoseconds(delay.nanoseconds))
    }
}
