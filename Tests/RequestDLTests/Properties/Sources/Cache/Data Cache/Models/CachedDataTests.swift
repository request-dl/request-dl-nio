//
// See LICENSE for this package's licensing information.
//

import SystemPackage
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
// import struct Foundation.Data
// import struct Foundation.Date
// import struct Foundation.URL
// import struct Foundation.UUID
#endif

struct CachedDataTests {

    /// Owns a scratch file for the lifetime of one test.
    final class FileURLManager: Sendable {

        let url: URL

        init() async throws {
            url = URL(fileURLWithPath: FilePath.temporaryDirectory.string, isDirectory: true)
                .appendingPathComponent("CachedDataTests.\(UUID().uuidString).txt")

            try await url.removeIfNeeded()
        }

        deinit {
            let url = self.url
            Task.detached { try? await url.removeIfNeeded() }
        }
    }

    func mockResponse(url: String) -> ResponseHead {
        ResponseHead(
            url: URL(string: url),
            status: .init(code: 200, reason: "Ok"),
            version: .init(minor: 1, major: 2),
            headers: HTTPHeaders([("ETag", "\(UUID())")]),
            isKeepAlive: false
        )
    }

    @Test
    func cachedData_whenInitWithData_shouldExposePolicy() async throws {
        // Given
        let policy: DataCache.Policy.Set = .memory

        // When
        let cachedData = await CachedData(
            response: mockResponse(url: "https://apple.com"),
            policy: policy,
            data: Data("Hello world".utf8)
        )

        // Then
        #expect(cachedData.policy == policy)
    }

    @Test
    func cachedData_whenInitWithURL_shouldReadFileBackedData() async throws {
        // Given
        let fileURLManager = try await FileURLManager()
        defer { _ = fileURLManager }

        let fileURL = fileURLManager.url
        let data = Data("Hello from disk".utf8)
        try data.write(to: fileURL)

        let policy: DataCache.Policy.Set = .disk

        // When
        let cachedData = await CachedData(
            response: mockResponse(url: "https://google.com"),
            policy: policy,
            url: fileURL
        )

        // Then
        #expect(cachedData.policy == policy)
        #expect(cachedData.response.url == URL(string: "https://google.com"))
        let cachedDataBytes = await cachedData.data
        #expect(cachedDataBytes == data)
    }

    @Test
    func cachedData_whenResponseHasNoURL_roundTripsAsNil() async throws {
        // Given
        let response = ResponseHead(
            url: nil,
            status: .init(code: 200, reason: "Ok"),
            version: .init(minor: 1, major: 2),
            headers: HTTPHeaders(),
            isKeepAlive: false
        )

        // When
        let cachedData = await CachedData(
            response: response,
            policy: .memory,
            data: Data("no url".utf8)
        )

        // Then
        #expect(cachedData.response.url == nil)
    }
}
