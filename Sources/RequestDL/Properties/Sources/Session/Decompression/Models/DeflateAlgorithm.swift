//
// See LICENSE for this package's licensing information.
//

/// Deflate, both directions.
///
/// As a ``Decompressor``, this is a placeholder standing in for decoding always performed
/// natively by the OS (`.urlSession`) or `async-http-client` (`.nio`/`.nioTransportServices`) --
/// never by this type. The `Decompressor` `callAsFunction()` throws ``NativeOnlyAlgorithmError``
/// if it's ever actually invoked, which only happens when mixed into the same list as a
/// genuinely custom algorithm. See ``Session/decompressionAlgorithms(_:limit:)``.
///
/// As a ``Compressor``, though, this does real work: there is no OS-provided shortcut for
/// compressing an outgoing body the way there is for decoding an incoming one, so the
/// `Compressor` `callAsFunction()` actually drives `NIOHTTPRequestCompressor`.
public struct DeflateAlgorithm: Compressor, Decompressor {

    // MARK: - Public properties

    public var contentEncodingValue: String { "deflate" }

    // MARK: - Inits

    public init() {}

    // MARK: - Public methods

    public func callAsFunction() throws -> any CompressorStream {
        try NIOHTTPCompressorStreamBridge(algorithm: .deflate)
    }

    public func callAsFunction() throws -> any DecompressorStream {
        throw NativeOnlyAlgorithmError(contentEncodingValue: contentEncodingValue)
    }
}

// MARK: - Compressor extension

extension Compressor where Self == DeflateAlgorithm {

    /// Compresses the outgoing request body with deflate.
    public static var deflate: Self { .init() }
}

// MARK: - Decompressor extension

extension Decompressor where Self == DeflateAlgorithm {

    /// Decodes deflate-encoded responses -- natively, by whichever executor the request resolves to.
    public static var deflate: Self { .init() }
}
