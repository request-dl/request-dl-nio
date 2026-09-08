//
// See LICENSE for this package's licensing information.
//

import NIOCore
import RequestDLInternals

/// Adapts a `RequestDL.Compressor` to `Internals.CompressionAlgorithm`, converting between this
/// module's public `[UInt8]`-based protocols and the `ByteBuffer`-based ones `Internals` --
/// shared by both transports -- can reference without depending back on this module.
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

/// Adapts a `RequestDL.CompressorStream` to `Internals.CompressorStream`.
private struct InternalsCompressorStreamAdapter: Internals.CompressorStream {

    // MARK: - Private properties

    private var stream: any CompressorStream

    // MARK: - Inits

    init(stream: any CompressorStream) {
        self.stream = stream
    }

    // MARK: - Internal methods

    mutating func callAsFunction(compressing bytes: ByteBuffer) throws -> ByteBuffer {
        ByteBuffer(bytes: try stream.callAsFunction(compressing: Array(bytes.readableBytesView)))
    }

    mutating func finish() throws -> ByteBuffer {
        ByteBuffer(bytes: try stream.finish())
    }
}
