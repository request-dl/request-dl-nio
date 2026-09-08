//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals

extension RequestConfiguration {

    /// Wraps ``body`` so it compresses as it streams when a `Compressor` is configured (via
    /// `Property.compression(_:onDuplicateHeader:shouldCompressBodyData:)`), and sets/removes
    /// `Content-Encoding`/`Content-Length` to match.
    ///
    /// Runs once, here, before this configuration ever reaches `build(eventLoop:)` (the `.nio`
    /// path) or `buildURLRequest()`/the streamed-upload path (the `.urlSession` path) --
    /// `RequestBody` backs the outgoing body identically for both, so wrapping it at this layer,
    /// instead of at the wire layer the way this package used to (a `NIOHTTPRequestCompressor`
    /// spliced into the `.nio` executor's connection pipeline, which only ever ran for HTTP/1.1
    /// and was entirely invisible to `.urlSession`), makes compression behave identically on
    /// every executor and every negotiated HTTP version.
    ///
    /// A no-op when there's no body, the body is empty, no `Compressor` is configured, or
    /// `shouldCompressBodyData` declines this body's size -- the common case, so callers that
    /// never touch `.compression(_:)` pay nothing here.
    ///
    /// - Important: Genuinely streamed -- `body.compressed(with:)` wraps `RequestBody` in an
    /// `Internals.CompressingByteSequence` that compresses each chunk as the transport pulls it,
    /// rather than draining the whole body into memory before compression starts. The final,
    /// on-the-wire size is only known once the whole body has streamed through, so
    /// `Content-Length` is removed here rather than set -- both executors fall back to chunked
    /// transfer encoding (`HTTPClient.Body.stream(length: nil, ...)` on `.nio`, URLSession's own
    /// length-less upload path) instead of declaring a byte count upfront.
    mutating func applyCompression() throws {
        guard let algorithm = compression, let body, body.totalSize > .zero else {
            return
        }

        if let shouldCompressBodyData, !shouldCompressBodyData(body.totalSize) {
            return
        }

        if let existingContentEncoding = headers.first(name: "Content-Encoding") {
            switch compressionDuplicateHeaderBehavior {
            case .error:
                throw DuplicateContentEncodingError(value: existingContentEncoding)
            case .skip:
                return
            case .replace:
                break
            }
        }

        self.body = body.compressed(with: algorithm)
        headers.set(name: "Content-Encoding", value: algorithm.contentEncodingValue)
        headers.remove(name: "Content-Length")
    }
}
