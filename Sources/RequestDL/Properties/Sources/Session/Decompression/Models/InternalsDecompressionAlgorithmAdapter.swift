//
// See LICENSE for this package's licensing information.
//

import NIOCore
import RequestDLInternals

/// Adapts a `RequestDL.Decompressor` to `Internals.DecompressionAlgorithm`, converting between
/// this module's public `[UInt8]`-based protocols and the `ByteBuffer`-based ones `Internals` --
/// shared by both transports -- can reference without depending back on this module.
struct InternalsDecompressionAlgorithmAdapter: Internals.DecompressionAlgorithm {

    // MARK: - Internal properties

    let algorithm: any Decompressor

    // MARK: - Internal properties

    var contentEncodingValue: String {
        algorithm.contentEncodingValue
    }

    /// Not a `Decompressor` protocol requirement -- there is no legitimate reason for a
    /// third-party algorithm to declare itself URLSession-only today, so this stays a closed,
    /// structural check against the one built-in type that actually is, rather than a
    /// customization point every conformer would otherwise have to consider.
    var requiresURLSession: Bool {
        algorithm is BrotliURLSessionOnlyAlgorithm
    }

    /// A closed, structural check against the exact built-in types that are themselves nothing
    /// but placeholders for CFNetwork's own transparent decoding -- deliberately *not* a check
    /// against `contentEncodingValue`. A genuinely custom `Decompressor` that happens to declare
    /// `contentEncodingValue == "gzip"` is not `GzipAlgorithm`, so this stays `false` for it: it
    /// forces `.urlSession` into manual dispatch instead of silently letting CFNetwork decode the
    /// response before the custom algorithm ever runs.
    var isNativelyDecodedByURLSession: Bool {
        algorithm is GzipAlgorithm || algorithm is DeflateAlgorithm || algorithm is BrotliURLSessionOnlyAlgorithm
    }

    /// Same structural check as `isNativelyDecodedByURLSession`, minus `BrotliURLSessionOnlyAlgorithm`
    /// -- `NIOHTTPCompression` has no brotli decoder for `.nio`/`.nioTransportServices` to defer to
    /// at all, native or otherwise.
    var isNativelyDecodedByNIO: Bool {
        algorithm is GzipAlgorithm || algorithm is DeflateAlgorithm
    }

    // MARK: - Internal methods

    func callAsFunction() throws -> any Internals.DecompressorStream {
        InternalsDecompressorStreamAdapter(stream: try algorithm())
    }
}

/// Adapts a `RequestDL.DecompressorStream` to `Internals.DecompressorStream`.
private struct InternalsDecompressorStreamAdapter: Internals.DecompressorStream {

    // MARK: - Private properties

    private var stream: any DecompressorStream

    // MARK: - Inits

    init(stream: any DecompressorStream) {
        self.stream = stream
    }

    // MARK: - Internal methods

    mutating func callAsFunction(decompressing bytes: ByteBuffer) throws -> ByteBuffer {
        ByteBuffer(bytes: try stream.callAsFunction(decompressing: Array(bytes.readableBytesView)))
    }

    mutating func finish() throws -> ByteBuffer {
        ByteBuffer(bytes: try stream.finish())
    }
}
