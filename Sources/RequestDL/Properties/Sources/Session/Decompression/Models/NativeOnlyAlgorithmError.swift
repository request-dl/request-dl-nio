//
// See LICENSE for this package's licensing information.
//

/// Thrown by ``GzipAlgorithm``, ``DeflateAlgorithm``, and ``BrotliURLSessionOnlyAlgorithm`` if
/// their ``Decompressor/callAsFunction()`` is ever actually invoked.
///
/// In the normal case it never is: URLSession or `async-http-client` decodes these natively, and
/// RequestDL never has to. It's only reached when one of these is mixed into
/// ``Session/decompressionAlgorithms(_:limit:)`` alongside a genuinely custom algorithm --
/// mixing forces `.urlSession` to take over `Accept-Encoding` entirely (see
/// ``Session/decompressionAlgorithms(_:limit:)``'s documentation), which means it also has to
/// decode everything in the list itself, including the natives this type stands in for.
public struct NativeOnlyAlgorithmError: Error, Sendable {

    /// The `Content-Encoding` this algorithm claims to handle.
    public let contentEncodingValue: String
}

// MARK: - CustomStringConvertible

extension NativeOnlyAlgorithmError: CustomStringConvertible {

    public var description: String {
        """
        RequestDL could not decode a "\(contentEncodingValue)" response manually because this \
        algorithm only works through the OS/library's own native handling, which requires \
        running alone. Remove the custom algorithm mixed into the same \
        .decompressionAlgorithms(_:limit:) call, or provide your own \
        "\(contentEncodingValue)" decoder instead of this built-in one.
        """
    }
}
