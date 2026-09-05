//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOEmbedded
import NIOHTTP1
import NIOHTTPCompression

extension Internals.Compression.Algorithm {

    /// The wire name this algorithm's `Content-Encoding` value takes -- `NIOCompression
    /// .Algorithm`'s own `description`, so this always matches whatever `NIOHTTPRequestCompressor`
    /// itself would have written into the header.
    package var contentEncodingValue: String {
        build().description
    }

    /// Compresses `buffer` as a whole, using the same codec `NIOHTTPRequestCompressor` applies on
    /// the wire for the `.nio` executor.
    ///
    /// Driven through an `EmbeddedChannel` rather than a live connection pipeline: by the time
    /// this runs, the whole body is already sitting in memory as one `ByteBuffer` (see
    /// `RequestConfiguration.applyCompression(_:onDuplicateHeader:)`), not arriving in wire order
    /// the way a real HTTP/1.1 connection would hand it to that handler chunk by chunk. Reusing
    /// the handler itself -- rather than binding `CNIOExtrasZlib` directly, which isn't a public
    /// product of `swift-nio-extras` -- keeps this byte-for-byte identical to what the old
    /// connection-pipeline-only implementation produced.
    package func compress(_ buffer: ByteBuffer) throws -> ByteBuffer {
        let channel = EmbeddedChannel()
        defer { _ = try? channel.finish() }

        try channel.pipeline.syncOperations.addHandler(
            NIOHTTPRequestCompressor(encoding: build())
        )

        let head = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/")
        try channel.writeOutbound(HTTPClientRequestPart.head(head))
        try channel.writeOutbound(HTTPClientRequestPart.body(.byteBuffer(buffer)))
        try channel.writeOutbound(HTTPClientRequestPart.end(nil))

        var compressed = channel.allocator.buffer(capacity: buffer.readableBytes)

        while let part = try channel.readOutbound(as: HTTPClientRequestPart.self) {
            guard case .body(.byteBuffer(var chunk)) = part else {
                continue
            }

            compressed.writeBuffer(&chunk)
        }

        return compressed
    }
}
