//
// See LICENSE for this package's licensing information.
//

/// Thrown by ``GzipAlgorithm``, ``DeflateAlgorithm``, and ``BrotliURLSessionOnlyAlgorithm`` if
/// their ``Decompressor/callAsFunction()`` is ever actually invoked.
///
/// A session never does: URLSession or `async-http-client` decodes these natively, and RequestDL
/// never has to. That holds in a list that also contains a genuinely custom algorithm too: such a
/// list makes `.urlSession` take over `Accept-Encoding`, but it then announces and decodes only
/// the custom algorithms (see ``Session/decompressionAlgorithms(_:limit:)``), and `.nio` leaves
/// gzip/deflate to `async-http-client`. So the placeholders are never dispatched to, and a
/// native encoding the server sends anyway to a list that took over `Accept-Encoding` is an
/// ``UnsupportedContentEncodingError``, not this.
///
/// This is what's left for calling one of these placeholders' ``Decompressor/callAsFunction()``
/// directly, which has nothing to decode with.
///
/// Up to 4.5.8 a session could reach it: `[.gzip, custom]` on `.urlSession` announced
/// `gzip, custom`, and a gzip response then failed with this error.
public struct NativeOnlyAlgorithmError: Error, Sendable {

    /// The `Content-Encoding` this algorithm claims to handle.
    public let contentEncodingValue: String
}

// MARK: - CustomStringConvertible

extension NativeOnlyAlgorithmError: CustomStringConvertible {

    public var description: String {
        """
        This built-in algorithm cannot decode a "\(contentEncodingValue)" body itself: it only \
        stands for the decoding the OS or the library does natively. Provide your own \
        "\(contentEncodingValue)" Decompressor if RequestDL has to decode it.
        """
    }
}
