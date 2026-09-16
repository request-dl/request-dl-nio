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
/// compressing an outgoing body the way there is for decoding an incoming one. With NIO
/// available, `callAsFunction()` drives `NIOHTTPRequestCompressor`, streaming in bounded memory;
/// without it, `PortableGzipCompressorStream` produces the same gzip-wrapped wire format using
/// Foundation + the `Compression` framework instead, buffering the whole body rather than
/// streaming it. See that type's own doc comment for why. If even `zlib` isn't importable, this
/// falls back to ``CompressionUnavailableError`` like ``DeflateAlgorithm`` does in the same case.
public struct GzipAlgorithm: Compressor, Decompressor {

    // MARK: - Public properties

    public var contentEncodingValue: String { "gzip" }

    // MARK: - Inits

    public init() {}

    // MARK: - Public methods

    public func callAsFunction() throws -> any CompressorStream {
        #if canImport(NIOCore)
        try NIOHTTPCompressorStreamBridge(algorithm: .gzip)
        #elseif canImport(zlib)
        PortableGzipCompressorStream()
        #else
        throw CompressionUnavailableError(contentEncodingValue: contentEncodingValue)
        #endif
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
