//
// See LICENSE for this package's licensing information.
//

/// Thrown by ``GzipAlgorithm``/``DeflateAlgorithm``'s ``Compressor/callAsFunction()`` when
/// neither of their compression backends is available.
///
/// Compressing an outgoing body has no OS-provided shortcut the way decoding an incoming one
/// does, so these built-ins do real work as a ``Compressor`` rather than standing in for
/// something the transport already does. Both algorithms drive `NIOHTTPRequestCompressor` when
/// NIO is available, and fall back to a portable, `zlib`-backed implementation otherwise
/// (``PortableGzipCompressorStream``/``PortableDeflateCompressorStream``). This error only fires
/// in the narrowest case: NIO *and* `zlib` both unavailable, which, outside of a build the
/// package doesn't actually support yet, shouldn't happen in practice.
public struct CompressionUnavailableError: Error, Sendable {

    /// The `Content-Encoding` this algorithm would have compressed with.
    public let contentEncodingValue: String
}

// MARK: - CustomStringConvertible

extension CompressionUnavailableError: CustomStringConvertible {

    public var description: String {
        """
        RequestDL could not compress the request body as "\(contentEncodingValue)" because this \
        build has no backend available to do it with. Provide your own \
        "\(contentEncodingValue)" Compressor instead of this built-in one, or build with NIO \
        available.
        """
    }
}
