//
// See LICENSE for this package's licensing information.
//

import Foundation
import Testing

@testable import RequestDL

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
}

// MARK: - Test helpers

private struct StubImageTask: RequestTask {

    let onResult: @Sendable () async throws -> TaskResult<Data>

    func result() async throws -> TaskResult<Data> {
        try await onResult()
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
