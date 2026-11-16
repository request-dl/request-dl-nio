//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import NIOCore
import NIOEmbedded
import NIOHTTP1
import NIOHTTPCompression
import Testing

@testable import RequestDLInternals

struct InternalsBodylessResponseTests {

    private func head(_ status: HTTPResponseStatus, _ headers: [(String, String)] = []) -> HTTPResponseHead {
        HTTPResponseHead(version: .http1_1, status: status, headers: HTTPHeaders(headers))
    }

    // MARK: - What has no body

    @Test
    func aResponseToHEAD_hasNoBodyWhateverItSays() {
        let bodyless = Internals.BodylessResponse(method: .HEAD)

        #expect(bodyless.isBodyless(head(.ok, [("Content-Length", "40")])))
    }

    @Test(arguments: [HTTPResponseStatus.noContent, .notModified, .continue, .switchingProtocols])
    func aResponseWithAStatusThatHasNoBody_hasNoBody(_ status: HTTPResponseStatus) {
        let bodyless = Internals.BodylessResponse(method: .GET)

        #expect(bodyless.isBodyless(head(status)))
    }

    @Test
    func anEmptyResponse_hasNoBody() {
        let bodyless = Internals.BodylessResponse(method: .GET)

        #expect(bodyless.isBodyless(head(.ok, [("Content-Length", " 0 ")])))
    }

    @Test
    func aResponseThatMayHaveABody_hasOne() {
        let bodyless = Internals.BodylessResponse(method: .GET)

        #expect(!bodyless.isBodyless(head(.ok)))
        #expect(!bodyless.isBodyless(head(.ok, [("Content-Length", "10")])))
        #expect(!bodyless.isBodyless(head(.ok, [("Transfer-Encoding", "chunked")])))
    }

    @Test
    func onlyTheTruncatedDecoder_isWhatItRecognises() {
        let bodyless = Internals.BodylessResponse(method: .GET)

        #expect(bodyless.isTruncatedDecoder(NIOHTTPDecompression.ExtraDecompressionError.truncatedData))
        #expect(!bodyless.isTruncatedDecoder(NIOHTTPDecompression.ExtraDecompressionError.invalidTrailingData))
        #expect(!bodyless.isTruncatedDecoder(NIOHTTPDecompression.DecompressionError.inflationError(1)))
        #expect(!bodyless.isTruncatedDecoder(ChannelError.eof))
    }

    // MARK: - What is being worked around

    /// `NIOHTTPResponseDecompressor` (swift-nio-extras) fails a response that has no body and names
    /// `gzip` or `deflate`, because its decoder is asked to finish a stream it was never given.
    ///
    /// This is what `Internals.BodylessResponse` exists for. Should this ever stop failing, the
    /// handler has been fixed upstream and that type, and what uses it, can go.
    @Test(arguments: ["gzip", "deflate"])
    func theNIODecompressor_failsAResponseWithNoBody(_ encoding: String) throws {
        // Given
        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .none))

        // When
        try channel.writeInbound(
            HTTPClientResponsePart.head(head(.ok, [("Content-Encoding", encoding), ("Content-Length", "40")]))
        )

        // Then: the head went through, and the end of the message is what fails.
        #expect(throws: NIOHTTPDecompression.ExtraDecompressionError.truncatedData) {
            try channel.writeInbound(HTTPClientResponsePart.end(nil))
        }
    }
}

#endif
