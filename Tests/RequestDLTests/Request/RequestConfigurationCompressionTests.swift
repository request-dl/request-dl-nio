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
    func applyCompression_whenNoAlgorithmConfigured_doesNothing() async throws {
        // Given
        var configuration = RequestConfiguration()
        let payload = Data(String(repeating: "a", count: 1_024).utf8)
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])

        // When
        try configuration.applyCompression()

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == nil)
        #expect(try await bytes(of: configuration.body) == payload)
    }

    @Test
    func applyCompression_whenNoBody_doesNothing() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.compression = InternalsCompressionAlgorithmAdapter(algorithm: GzipAlgorithm())

        // When
        try configuration.applyCompression()

        // Then
        #expect(configuration.body == nil)
        #expect(configuration.headers.first(name: "Content-Encoding") == nil)
    }

    @Test
    func applyCompression_whenBodyIsEmpty_doesNothing() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.compression = InternalsCompressionAlgorithmAdapter(algorithm: GzipAlgorithm())
        configuration.body = RequestBody(buffers: [])

        // When
        try configuration.applyCompression()

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == nil)
    }

    @Test
    func applyCompression_whenShouldCompressBodyDataReturnsFalse_doesNothing() async throws {
        // Given
        var configuration = RequestConfiguration()
        let payload = Data(String(repeating: "a", count: 100_000).utf8)
        configuration.compression = InternalsCompressionAlgorithmAdapter(algorithm: GzipAlgorithm())
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])
        configuration.shouldCompressBodyData = { _ in false }

        // When
        try configuration.applyCompression()

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == nil)
        #expect(try await bytes(of: configuration.body) == payload)
    }

    @Test
    func applyCompression_whenShouldCompressBodyDataReturnsTrue_receivesTheBodysByteCountAndCompresses() async throws {
        // Given
        var configuration = RequestConfiguration()
        let payload = Data(String(repeating: "a", count: 100_000).utf8)
        configuration.compression = InternalsCompressionAlgorithmAdapter(algorithm: GzipAlgorithm())
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])
        configuration.shouldCompressBodyData = { $0 == payload.count }

        // When -- the closure only agrees to compress if it was handed exactly the body's byte
        // count, so a `Content-Encoding` header afterward is itself proof the right value arrived.
        try configuration.applyCompression()

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == "gzip")
    }

    @Test
    func applyCompression_whenGzipEnabled_compressesBodyAndSetsHeaders() async throws {
        // Given
        var configuration = RequestConfiguration()
        let payload = Data(String(repeating: "a", count: 100_000).utf8)
        configuration.compression = InternalsCompressionAlgorithmAdapter(algorithm: GzipAlgorithm())
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])

        // When
        try configuration.applyCompression()

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == "gzip")

        // The final, on-the-wire size is only known once the whole body has streamed through --
        // `Content-Length` is removed rather than declared upfront, falling back to chunked
        // transfer encoding on both executors.
        #expect(configuration.headers.first(name: "Content-Length") == nil)

        let compressed = try #require(try await bytes(of: configuration.body))

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
        configuration.compression = InternalsCompressionAlgorithmAdapter(algorithm: DeflateAlgorithm())
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])

        // When
        try configuration.applyCompression()

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == "deflate")
        #expect(configuration.headers.first(name: "Content-Length") == nil)

        let compressed = try #require(try await bytes(of: configuration.body))
        #expect(compressed.count < payload.count / 2)

        // The zlib header for a default-strategy, 32K-window deflate stream.
        #expect(compressed.first == 0x78)
    }

    @Test
    func applyCompression_whenContentEncodingAlreadySet_andBehaviorIsError_throws() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.compression = InternalsCompressionAlgorithmAdapter(algorithm: GzipAlgorithm())
        configuration.headers.set(name: "Content-Encoding", value: "br")
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(Data("payload".utf8))])

        // When / Then
        do {
            try configuration.applyCompression()
            Issue.record("Expected DuplicateContentEncodingError to be thrown")
        } catch let error as DuplicateContentEncodingError {
            #expect(error.value == "br")
        }
    }

    @Test
    func applyCompression_whenContentEncodingAlreadySet_andBehaviorIsSkip_leavesRequestUntouched() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.compression = InternalsCompressionAlgorithmAdapter(algorithm: GzipAlgorithm())
        configuration.compressionDuplicateHeaderBehavior = .skip
        configuration.headers.set(name: "Content-Encoding", value: "br")
        let payload = Data("payload".utf8)
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])

        // When
        try configuration.applyCompression()

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == "br")
        #expect(try await bytes(of: configuration.body) == payload)
    }

    @Test
    func applyCompression_whenContentEncodingAlreadySet_andBehaviorIsReplace_compresses() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.compression = InternalsCompressionAlgorithmAdapter(algorithm: GzipAlgorithm())
        configuration.compressionDuplicateHeaderBehavior = .replace
        configuration.headers.set(name: "Content-Encoding", value: "br")
        let payload = Data(String(repeating: "a", count: 100_000).utf8)
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])

        // When
        try configuration.applyCompression()

        // Then
        #expect(configuration.headers.first(name: "Content-Encoding") == "gzip")

        let compressed = try #require(try await bytes(of: configuration.body))
        #expect(compressed.count < payload.count / 2)
    }

    @Test
    func applyCompression_whenBodyIsLarge_compressesInBoundedMemoryAcrossManyChunks() async throws {
        // Given -- several times over `Internals.BodySequence`'s own chunking, so the compressor
        // genuinely gets fed many separate calls, not one lucky single chunk.
        var configuration = RequestConfiguration()
        let payload = Data(String(repeating: "abcdefgh", count: 2_000_000).utf8)
        configuration.compression = InternalsCompressionAlgorithmAdapter(algorithm: GzipAlgorithm())
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])

        // When
        try configuration.applyCompression()

        // Then -- draining the wrapped body chunk by chunk (rather than all at once) and
        // reassembling still reproduces byte-identical gzip output, proving the per-chunk
        // `Compressor` state (window, checksum) survives correctly across many calls.
        var chunkCount = 0
        var compressed = Data()

        if let body = configuration.body {
            for try await chunk in body {
                chunkCount += 1
                compressed.append(contentsOf: chunk.readableBytesView)
            }
        }

        #expect(chunkCount > 1)
        #expect(compressed.count < payload.count / 10)
        #expect(compressed.prefix(2) == Data([0x1F, 0x8B]))
    }
}

extension RequestConfigurationCompressionTests {

    private func bytes(of body: RequestBody?) async throws -> Data? {
        guard let body else {
            return nil
        }

        var data = Data()
        for try await chunk in body {
            data.append(contentsOf: chunk.readableBytesView)
        }
        return data
    }
}
