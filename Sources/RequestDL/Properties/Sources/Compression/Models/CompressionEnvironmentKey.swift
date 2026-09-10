//
// See LICENSE for this package's licensing information.
//

private struct CompressionKey: RequestEnvironmentKey {
    static var defaultValue: (any Compressor)? { nil }
}

private struct CompressionDuplicateHeaderBehaviorKey: RequestEnvironmentKey {
    static var defaultValue: CompressionDuplicateHeaderBehavior { .error }
}

private struct ShouldCompressBodyDataKey: RequestEnvironmentKey {
    static var defaultValue: (@Sendable (Int) -> Bool)? { nil }
}

extension RequestEnvironmentValues {

    var compression: (any Compressor)? {
        get { self[CompressionKey.self] }
        set { self[CompressionKey.self] = newValue }
    }

    var compressionDuplicateHeaderBehavior: CompressionDuplicateHeaderBehavior {
        get { self[CompressionDuplicateHeaderBehaviorKey.self] }
        set { self[CompressionDuplicateHeaderBehaviorKey.self] = newValue }
    }

    var shouldCompressBodyData: (@Sendable (Int) -> Bool)? {
        get { self[ShouldCompressBodyDataKey.self] }
        set { self[ShouldCompressBodyDataKey.self] = newValue }
    }
}

extension Property {

    ///
    /// Compresses the outgoing request body before it's sent, setting the `Content-Encoding`
    /// header accordingly.
    ///
    /// Unlike response decompression (``Session/decompressionAlgorithms(_:limit:)``), this is
    /// attached near the body itself, not the session: it's environment-driven, the same way
    /// ``Property/payloadEncoder(_:)`` is, so it applies to every `Payload`/`Form` in scope.
    ///
    /// It's also independent of which ``Session/Executor`` the request resolves to. The body is
    /// compressed once, up front, so `.urlSession`/`.nioTransportServices`/`.nio` and every
    /// negotiated HTTP version all see the same already-compressed bytes.
    ///
    /// Compression is only worth its CPU cost for bodies that are both sizable and not already
    /// compressed (a large JSON payload, say, but not an image). Use `shouldCompressBodyData`
    /// to gate it on the body's byte count, the same threshold Alamofire's own
    /// `DeflateRequestCompressor.shouldCompressBodyData` recommends. Left `nil`, every request
    /// with a body is compressed whenever a `Compressor` is configured, regardless of size.
    ///
    /// - Parameters:
    ///   - algorithm: The algorithm used to compress the request body.
    ///   - behavior: What to do if the request already carries a `Content-Encoding` header.
    ///   Defaults to ``CompressionDuplicateHeaderBehavior/error``.
    ///   - shouldCompressBodyData: Given the outgoing body's byte count, decides whether to
    ///   compress it. Defaults to `nil`, which always compresses.
    /// - Returns: A modified property with request-body compression configured.
    ///
    public func compression<Algorithm: Compressor>(
        _ algorithm: Algorithm,
        onDuplicateHeader behavior: CompressionDuplicateHeaderBehavior = .error,
        shouldCompressBodyData: (@Sendable (Int) -> Bool)? = nil
    ) -> some Property {
        environment(\.compression, algorithm)
            .environment(\.compressionDuplicateHeaderBehavior, behavior)
            .environment(\.shouldCompressBodyData, shouldCompressBodyData)
    }
}
