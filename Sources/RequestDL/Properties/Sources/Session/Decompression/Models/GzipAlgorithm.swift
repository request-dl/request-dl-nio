//
// See LICENSE for this package's licensing information.
//

/// Gzip, both directions.
///
/// As a ``Decompressor``, this is a placeholder standing in for decoding always performed
/// natively by the OS (`.urlSession`) or `async-http-client` (`.nio`/`.nioTransportServices`),
/// never by this type. The `Decompressor` `callAsFunction()` throws ``NativeOnlyAlgorithmError``
/// if it's ever actually invoked, which only happens when mixed into the same list as a
/// genuinely custom algorithm. See ``Session/decompressionAlgorithms(_:limit:)``.
///
/// As a ``Compressor``, though, this does real work: there is no OS-provided shortcut for
/// compressing an outgoing body the way there is for decoding an incoming one, so the
/// `Compressor` `callAsFunction()` actually drives `NIOHTTPRequestCompressor`.
public struct GzipAlgorithm: Compressor, Decompressor {

    // MARK: - Public properties

    public var contentEncodingValue: String { "gzip" }

    // MARK: - Inits

    public init() {}

    // MARK: - Public methods

    public func callAsFunction() throws -> any CompressorStream {
        try NIOHTTPCompressorStreamBridge(algorithm: .gzip)
    }

    public func callAsFunction() throws -> any DecompressorStream {
        throw NativeOnlyAlgorithmError(contentEncodingValue: contentEncodingValue)
    }
}

// MARK: - Compressor extension

extension Compressor where Self == GzipAlgorithm {

    /// Compresses the outgoing request body with gzip.
    public static var gzip: Self { .init() }
}

// MARK: - Decompressor extension

extension Decompressor where Self == GzipAlgorithm {

    /// Decodes gzip-encoded responses natively, by whichever executor the request resolves to.
    public static var gzip: Self { .init() }
}
