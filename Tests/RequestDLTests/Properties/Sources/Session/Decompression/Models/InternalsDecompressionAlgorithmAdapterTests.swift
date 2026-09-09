//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

struct InternalsDecompressionAlgorithmAdapterTests {

    /// A genuinely custom `Decompressor` that happens to claim the same `contentEncodingValue`
    /// as a built-in placeholder -- exactly the shape a caller would reach for to replace
    /// ``GzipAlgorithm``'s (silent, OS-native) handling with their own logic.
    private struct CustomAlgorithm: Decompressor {
        let contentEncodingValue: String

        func callAsFunction() throws -> any DecompressorStream {
            fatalError("not exercised")
        }
    }

    @Test
    func isNativelyDecodedByURLSession_whenGzipAlgorithm_isTrue() {
        #expect(InternalsDecompressionAlgorithmAdapter(algorithm: GzipAlgorithm()).isNativelyDecodedByURLSession)
    }

    @Test
    func isNativelyDecodedByURLSession_whenDeflateAlgorithm_isTrue() {
        #expect(InternalsDecompressionAlgorithmAdapter(algorithm: DeflateAlgorithm()).isNativelyDecodedByURLSession)
    }

    @Test
    func isNativelyDecodedByURLSession_whenBrotliURLSessionOnlyAlgorithm_isTrue() {
        #expect(
            InternalsDecompressionAlgorithmAdapter(algorithm: BrotliURLSessionOnlyAlgorithm())
                .isNativelyDecodedByURLSession
        )
    }

    @Test(arguments: ["gzip", "deflate", "br", "zstd"])
    func isNativelyDecodedByURLSession_whenCustomAlgorithm_isFalseRegardlessOfContentEncodingValue(
        contentEncodingValue: String
    ) {
        // A custom algorithm claiming "gzip"/"deflate"/"br" must NOT be mistaken for the built-in
        // placeholder that shares its wire name -- otherwise `.urlSession` would let CFNetwork
        // decode the response transparently and this algorithm would never actually run. Only
        // the three built-in types above -- which do nothing themselves -- get `true`.
        let adapter = InternalsDecompressionAlgorithmAdapter(
            algorithm: CustomAlgorithm(contentEncodingValue: contentEncodingValue)
        )

        #expect(!adapter.isNativelyDecodedByURLSession)
    }

    @Test
    func isNativelyDecodedByNIO_whenGzipAlgorithm_isTrue() {
        #expect(InternalsDecompressionAlgorithmAdapter(algorithm: GzipAlgorithm()).isNativelyDecodedByNIO)
    }

    @Test
    func isNativelyDecodedByNIO_whenDeflateAlgorithm_isTrue() {
        #expect(InternalsDecompressionAlgorithmAdapter(algorithm: DeflateAlgorithm()).isNativelyDecodedByNIO)
    }

    @Test
    func isNativelyDecodedByNIO_whenBrotliURLSessionOnlyAlgorithm_isFalse() {
        // `NIOHTTPCompression` has no brotli decoder at all, native or otherwise -- unlike
        // `isNativelyDecodedByURLSession`, brotli is never natively decoded here.
        #expect(
            !InternalsDecompressionAlgorithmAdapter(algorithm: BrotliURLSessionOnlyAlgorithm())
                .isNativelyDecodedByNIO
        )
    }

    @Test(arguments: ["gzip", "deflate", "br", "zstd"])
    func isNativelyDecodedByNIO_whenCustomAlgorithm_isFalseRegardlessOfContentEncodingValue(
        contentEncodingValue: String
    ) {
        // A custom algorithm claiming "gzip"/"deflate" must NOT be mistaken for the built-in
        // placeholder that shares its wire name -- otherwise `async-http-client`'s own
        // `NIOHTTPResponseDecompressor` would decode the response transparently and this
        // algorithm would never actually run.
        let adapter = InternalsDecompressionAlgorithmAdapter(
            algorithm: CustomAlgorithm(contentEncodingValue: contentEncodingValue)
        )

        #expect(!adapter.isNativelyDecodedByNIO)
    }

    @Test
    func requiresURLSession_whenBrotliURLSessionOnlyAlgorithm_isTrue() {
        #expect(InternalsDecompressionAlgorithmAdapter(algorithm: BrotliURLSessionOnlyAlgorithm()).requiresURLSession)
    }

    @Test
    func requiresURLSession_whenGzipOrCustomAlgorithm_isFalse() {
        #expect(!InternalsDecompressionAlgorithmAdapter(algorithm: GzipAlgorithm()).requiresURLSession)
        #expect(
            !InternalsDecompressionAlgorithmAdapter(algorithm: CustomAlgorithm(contentEncodingValue: "gzip"))
                .requiresURLSession
        )
    }
}
