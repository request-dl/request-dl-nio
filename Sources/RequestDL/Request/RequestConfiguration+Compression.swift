//
// See LICENSE for this package's licensing information.
//

import NIOCore
import RequestDLInternals

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

extension RequestConfiguration {

    /// Compresses ``body`` in place when `compression` is enabled, and sets `Content-Encoding`/
    /// `Content-Length` to match.
    ///
    /// Runs once, here, before this configuration ever reaches `build(eventLoop:)` (the `.nio`
    /// path) or `buildURLRequest()`/the streamed-upload path (the `.urlSession` path) --
    /// `RequestBody` backs the outgoing body identically for both, so compressing it at this
    /// layer, instead of at the wire layer the way this package used to (a
    /// `NIOHTTPRequestCompressor` spliced into the `.nio` executor's connection pipeline, which
    /// only ever ran for HTTP/1.1 and was entirely invisible to `.urlSession`), makes compression
    /// behave identically on every executor and every negotiated HTTP version.
    ///
    /// A no-op when there's no body, the body is empty, `compression` is `.disabled`, or
    /// `shouldCompressBodyData` declines this body's size -- the common case, so callers that
    /// never touch `Session.compression(_:)` pay nothing here.
    mutating func applyCompression(
        _ compression: Internals.Compression,
        onDuplicateHeader behavior: Internals.Compression.DuplicateHeaderBehavior,
        shouldCompressBodyData: (@Sendable (Int) -> Bool)?
    ) async throws {
        guard case .enabled(let algorithm) = compression, let body, body.totalSize > .zero else {
            return
        }

        if let shouldCompressBodyData, !shouldCompressBodyData(body.totalSize) {
            return
        }

        if let existingContentEncoding = headers.first(name: "Content-Encoding") {
            switch behavior {
            case .error:
                throw DuplicateContentEncodingError(value: existingContentEncoding)
            case .skip:
                return
            case .replace:
                break
            }
        }

        var buffer = ByteBufferAllocator().buffer(capacity: body.totalSize)

        for await chunk in body {
            var chunk = chunk
            buffer.writeBuffer(&chunk)
        }

        let compressed = try algorithm.compress(buffer)
        let compressedBody = await RequestBody(
            buffers: [Internals.DataBuffer(Data(compressed.readableBytesView))]
        )

        self.body = compressedBody
        headers.set(name: "Content-Encoding", value: algorithm.contentEncodingValue)
        headers.set(name: "Content-Length", value: String(compressedBody.totalSize))
    }
}
