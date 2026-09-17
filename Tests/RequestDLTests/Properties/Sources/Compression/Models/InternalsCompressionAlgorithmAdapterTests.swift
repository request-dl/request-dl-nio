//
// See LICENSE for this package's licensing information.
//

import NIOCore
import RequestDLInternals
import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

struct InternalsCompressionAlgorithmAdapterTests {

    /// Reverses each chunk and appends a fixed 2-byte trailer on `finish()`: not a realistic
    /// codec, just enough to prove bytes cross `InternalsCompressorStreamAdapter` unmodified,
    /// in order, and untruncated, for both `Internals.Bytes` storage backings.
    private struct ReversingCompressor: Compressor {
        let contentEncodingValue = "x-test-reverse"

        func callAsFunction() throws -> any CompressorStream {
            ReversingCompressorStream()
        }
    }

    private struct ReversingCompressorStream: CompressorStream {
        mutating func callAsFunction(compressing bytes: [UInt8]) throws -> [UInt8] {
            bytes.reversed()
        }

        mutating func finish() throws -> [UInt8] {
            [0xFF, 0xFE]
        }
    }

    @Test
    func contentEncodingValue_matchesTheWrappedCompressor() {
        // Given
        let adapter = InternalsCompressionAlgorithmAdapter(algorithm: ReversingCompressor())

        // Then
        #expect(adapter.contentEncodingValue == "x-test-reverse")
    }

    @Test
    func callAsFunction_whenDataBackedInput_streamsBytesThroughReversed() throws {
        // Given
        let adapter = InternalsCompressionAlgorithmAdapter(algorithm: ReversingCompressor())
        var stream = try adapter()

        // When
        var compressed = try stream(compressing: Internals.Bytes(Data("hello".utf8)))
        var trailer = try stream.finish()

        // Then
        #expect(compressed.asData() == Data(Array("hello".utf8).reversed()))
        #expect(trailer.asData() == Data([0xFF, 0xFE]))
    }

    @Test
    func callAsFunction_whenByteBufferBackedInput_streamsBytesThroughReversed() throws {
        // Given: exercises `Internals.Bytes.asBytes()`'s `.byteBuffer`-backed branch, not just
        // the `.data`-backed one above.
        let adapter = InternalsCompressionAlgorithmAdapter(algorithm: ReversingCompressor())
        var stream = try adapter()

        // When
        var compressed = try stream(compressing: Internals.Bytes(ByteBuffer(string: "hi")))

        // Then
        #expect(compressed.asData() == Data(Array("hi".utf8).reversed()))
    }

    // MARK: - Portable gzip/deflate fast path

    /// Constructs `PortableGzipCompressorStream`/`PortableDeflateCompressorStream` directly,
    /// bypassing `GzipAlgorithm`/`DeflateAlgorithm`'s own `#if canImport(NIOCore)` selection
    /// (which, in this test build, always picks `NIOHTTPCompressorStreamBridge` instead): proves
    /// `InternalsCompressionAlgorithmAdapter` recognizes them too, not just the NIOCore bridge.
    private struct FakePortableGzipCompressor: Compressor {
        let contentEncodingValue = "gzip"
        func callAsFunction() throws -> any CompressorStream {
            try PortableGzipCompressorStream()
        }
    }

    private struct FakePortableDeflateCompressor: Compressor {
        let contentEncodingValue = "deflate"
        func callAsFunction() throws -> any CompressorStream {
            try PortableDeflateCompressorStream()
        }
    }

    @Test
    func callAsFunction_whenPortableGzipCompressorStream_bypassesTheByteArrayAdapter() throws {
        // Given
        let adapter = InternalsCompressionAlgorithmAdapter(algorithm: FakePortableGzipCompressor())
        var stream = try adapter()

        // Then: the `Internals.Bytes`-native fast path, not `InternalsCompressorStreamAdapter`'s
        // `[UInt8]` round trip.
        #expect(stream is PortableZlibCompressorNativeStream)

        // When
        var compressed = try stream(compressing: Internals.Bytes(Data("hello".utf8)))
        var trailer = try stream.finish()
        var wholeStream = compressed.asData()
        wholeStream.append(trailer.asData())

        // Then: still produces a valid gzip stream through the native path.
        #expect(wholeStream.prefix(3) == Data([0x1F, 0x8B, 0x08]))
    }

    @Test
    func callAsFunction_whenPortableDeflateCompressorStream_bypassesTheByteArrayAdapter() throws {
        // Given
        let adapter = InternalsCompressionAlgorithmAdapter(algorithm: FakePortableDeflateCompressor())
        var stream = try adapter()

        // Then
        #expect(stream is PortableZlibCompressorNativeStream)

        // When
        var compressed = try stream(compressing: Internals.Bytes(Data("hello".utf8)))
        var trailer = try stream.finish()
        var wholeStream = compressed.asData()
        wholeStream.append(trailer.asData())

        // Then: still produces a valid zlib stream through the native path.
        #expect(wholeStream.prefix(2) == Data([0x78, 0x9C]))
    }
}
