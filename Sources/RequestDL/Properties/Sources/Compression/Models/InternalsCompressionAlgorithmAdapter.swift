//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// Adapts a `RequestDL.Compressor` to `Internals.CompressionAlgorithm`, converting between this
/// module's public `[UInt8]`-based protocols and the `Data`-based ones `Internals` (shared by
/// both transports) can reference without depending back on this module.
struct InternalsCompressionAlgorithmAdapter: Internals.CompressionAlgorithm {

    // MARK: - Internal properties

    let algorithm: any Compressor

    var contentEncodingValue: String {
        algorithm.contentEncodingValue
    }

    // MARK: - Internal methods

    func callAsFunction() throws -> any Internals.CompressorStream {
        InternalsCompressorStreamAdapter(stream: try algorithm())
    }
}

/// Adapts a `RequestDL.CompressorStream` to `Internals.CompressorStream`. Always `Data`-backed
/// on the way out: a custom, `[UInt8]`-based compressor has no `ByteBuffer` to preserve, unlike
/// `Internals.NIOHTTPCompressorStream`'s own conformance.
private struct InternalsCompressorStreamAdapter: Internals.CompressorStream {

    // MARK: - Private properties

    private var stream: any CompressorStream

    // MARK: - Inits

    init(stream: any CompressorStream) {
        self.stream = stream
    }

    // MARK: - Internal methods

    mutating func callAsFunction(compressing bytes: Internals.Bytes) throws -> Internals.Bytes {
        var bytes = bytes
        return Internals.Bytes(Data(try stream(compressing: Array(bytes.asData()))))
    }

    mutating func finish() throws -> Internals.Bytes {
        Internals.Bytes(Data(try stream.finish()))
    }
}
