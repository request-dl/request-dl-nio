//
// See LICENSE for this package's licensing information.
//

import NIOCore
import RequestDLInternals

/// Bridges `Internals.NIOHTTPCompressorStream` (`ByteBuffer`-based) onto the public,
/// `[UInt8]`-based ``CompressorStream`` -- backs ``GzipAlgorithm``/``DeflateAlgorithm``, the only
/// two built-in ``Compressor``s that do real work rather than throw
/// ``NativeOnlyAlgorithmError``, since there is no OS-provided outgoing-compression shortcut
/// either of them could defer to instead.
struct NIOHTTPCompressorStreamBridge: CompressorStream {

    // MARK: - Private properties

    private var stream: Internals.NIOHTTPCompressorStream

    // MARK: - Inits

    init(algorithm: Internals.Compression.Algorithm) throws {
        stream = try Internals.NIOHTTPCompressorStream(algorithm: algorithm)
    }

    // MARK: - Internal methods

    mutating func callAsFunction(compressing bytes: [UInt8]) throws -> [UInt8] {
        Array(try stream.callAsFunction(compressing: ByteBuffer(bytes: bytes)).readableBytesView)
    }

    mutating func finish() throws -> [UInt8] {
        Array(try stream.finish().readableBytesView)
    }
}
