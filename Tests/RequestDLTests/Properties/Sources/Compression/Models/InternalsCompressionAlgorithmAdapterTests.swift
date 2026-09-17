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
}
