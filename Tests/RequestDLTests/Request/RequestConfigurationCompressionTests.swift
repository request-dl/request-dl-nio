//
// See LICENSE for this package's licensing information.
//

import NIOCore
import Testing

@testable import RequestDL
@testable import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct RequestConfigurationCompressionTests {

    @Test
    func applyCompression_whenDisabled_doesNothing() async throws {
        // Given
        var configuration = RequestConfiguration()
        let payload = Data(String(repeating: "a", count: 1_024).utf8)
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])

        // When
        try await configuration.applyCompression(.disabled, onDuplicateHeader: .error, shouldCompressBodyData: nil)

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == nil)
        #expect(await bytes(of: configuration.body) == payload)
    }

    @Test
    func applyCompression_whenNoBody_doesNothing() async throws {
        // Given
        var configuration = RequestConfiguration()

        // When
        try await configuration.applyCompression(
            .enabled(.gzip),
            onDuplicateHeader: .error,
            shouldCompressBodyData: nil
        )

        // Then
        #expect(configuration.body == nil)
        #expect(configuration.headers.first(name: "Content-Encoding") == nil)
    }

    @Test
    func applyCompression_whenBodyIsEmpty_doesNothing() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.body = RequestBody(buffers: [])

        // When
        try await configuration.applyCompression(
            .enabled(.gzip),
            onDuplicateHeader: .error,
            shouldCompressBodyData: nil
        )

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == nil)
    }

    @Test
    func applyCompression_whenShouldCompressBodyDataReturnsFalse_doesNothing() async throws {
        // Given
        var configuration = RequestConfiguration()
        let payload = Data(String(repeating: "a", count: 100_000).utf8)
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])

        // When
        try await configuration.applyCompression(
            .enabled(.gzip),
            onDuplicateHeader: .error,
            shouldCompressBodyData: { _ in false }
        )

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == nil)
        #expect(await bytes(of: configuration.body) == payload)
    }

    @Test
    func applyCompression_whenShouldCompressBodyDataReturnsTrue_receivesTheBodysByteCountAndCompresses() async throws {
        // Given
        var configuration = RequestConfiguration()
        let payload = Data(String(repeating: "a", count: 100_000).utf8)
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])

        // When -- the closure only agrees to compress if it was handed exactly the body's byte
        // count, so a `Content-Encoding` header afterward is itself proof the right value arrived.
        try await configuration.applyCompression(
            .enabled(.gzip),
            onDuplicateHeader: .error,
            shouldCompressBodyData: { $0 == payload.count }
        )

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == "gzip")
    }

    @Test
    func applyCompression_whenGzipEnabled_compressesBodyAndSetsHeaders() async throws {
        // Given
        var configuration = RequestConfiguration()
        let payload = Data(String(repeating: "a", count: 100_000).utf8)
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])

        // When
        try await configuration.applyCompression(
            .enabled(.gzip),
            onDuplicateHeader: .error,
            shouldCompressBodyData: nil
        )

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == "gzip")

        let compressed = try #require(await bytes(of: configuration.body))
        #expect(configuration.headers.first(name: "Content-Length") == String(compressed.count))

        // Highly compressible, so this leaves no doubt real compression happened, not a
        // pass-through.
        #expect(compressed.count < payload.count / 2)

        // The gzip magic number.
        #expect(compressed.prefix(2) == Data([0x1F, 0x8B]))
    }

    @Test
    func applyCompression_whenDeflateEnabled_compressesBodyAndSetsHeaders() async throws {
        // Given
        var configuration = RequestConfiguration()
        let payload = Data(String(repeating: "a", count: 100_000).utf8)
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])

        // When
        try await configuration.applyCompression(
            .enabled(.deflate),
            onDuplicateHeader: .error,
            shouldCompressBodyData: nil
        )

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == "deflate")

        let compressed = try #require(await bytes(of: configuration.body))
        #expect(configuration.headers.first(name: "Content-Length") == String(compressed.count))
        #expect(compressed.count < payload.count / 2)

        // The zlib header for a default-strategy, 32K-window deflate stream.
        #expect(compressed.first == 0x78)
    }

    @Test
    func applyCompression_whenContentEncodingAlreadySet_andBehaviorIsError_throws() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.headers.set(name: "Content-Encoding", value: "br")
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(Data("payload".utf8))])

        // When / Then
        do {
            try await configuration.applyCompression(
                .enabled(.gzip),
                onDuplicateHeader: .error,
                shouldCompressBodyData: nil
            )
            Issue.record("Expected DuplicateContentEncodingError to be thrown")
        } catch let error as DuplicateContentEncodingError {
            #expect(error.value == "br")
        }
    }

    @Test
    func applyCompression_whenContentEncodingAlreadySet_andBehaviorIsSkip_leavesRequestUntouched() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.headers.set(name: "Content-Encoding", value: "br")
        let payload = Data("payload".utf8)
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])

        // When
        try await configuration.applyCompression(.enabled(.gzip), onDuplicateHeader: .skip, shouldCompressBodyData: nil)

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == "br")
        #expect(await bytes(of: configuration.body) == payload)
    }

    @Test
    func applyCompression_whenContentEncodingAlreadySet_andBehaviorIsReplace_compresses() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.headers.set(name: "Content-Encoding", value: "br")
        let payload = Data(String(repeating: "a", count: 100_000).utf8)
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])

        // When
        try await configuration.applyCompression(
            .enabled(.gzip),
            onDuplicateHeader: .replace,
            shouldCompressBodyData: nil
        )

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == "gzip")

        let compressed = try #require(await bytes(of: configuration.body))
        #expect(compressed.count < payload.count / 2)
    }
}

extension RequestConfigurationCompressionTests {

    private func bytes(of body: RequestBody?) async -> Data? {
        guard let body else {
            return nil
        }

        var data = Data()
        for await chunk in body {
            data.append(contentsOf: chunk.readableBytesView)
        }
        return data
    }
}
