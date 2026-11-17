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

/// The decompressor of a real client pipeline, fed by hand: what reaches the handler behind it,
/// with and without `Internals.NothingToDecode` around it.
struct InternalsNothingToDecodeTests {

    // MARK: - Private methods

    private func channel(installing: Bool) throws -> EmbeddedChannel {
        let channel = EmbeddedChannel()
        try channel.pipeline.syncOperations.addHandler(NIOHTTPResponseDecompressor(limit: .none))

        if installing {
            try Internals.NothingToDecode.install(on: channel).wait()
        }

        return channel
    }

    private func head(_ status: HTTPResponseStatus, encoding: String? = "gzip") -> HTTPClientResponsePart {
        var headers = HTTPHeaders()

        if let encoding {
            headers.add(name: "Content-Encoding", value: encoding)
        }

        return .head(HTTPResponseHead(version: .http1_1, status: status, headers: headers))
    }

    private func body(_ bytes: [UInt8]) -> HTTPClientResponsePart {
        .body(ByteBuffer(bytes: bytes))
    }

    /// `"hello"`, gzip encoded.
    private static let gzipHello: [UInt8] = [
        0x1F, 0x8B, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x03, 0xCB, 0x48, 0xCD, 0xC9, 0xC9,
        0x07, 0x00, 0x86, 0xA6, 0x10, 0x36, 0x05, 0x00, 0x00, 0x00,
    ]

    // MARK: - Nothing to decode

    /// What happens without it, and why it exists: a redirect that names an encoding and has no
    /// body fails the request.
    @Test
    func withoutIt_aMessageWithNoBodyIsReportedAsTruncated() throws {
        let channel = try channel(installing: false)
        defer { _ = try? channel.finish() }

        try channel.writeInbound(head(.movedPermanently))
        // `EmbeddedChannel` throws what was caught from the write that caused it.
        #expect(throws: NIOHTTPDecompression.ExtraDecompressionError.truncatedData) {
            try channel.writeInbound(HTTPClientResponsePart.end(nil))
            try channel.throwIfErrorCaught()
        }
    }

    @Test(arguments: [HTTPResponseStatus.movedPermanently, .temporaryRedirect, .noContent, .notModified, .ok])
    func aMessageWithNoBody_endsWithoutAnError(_ status: HTTPResponseStatus) throws {
        let channel = try channel(installing: true)
        defer { _ = try? channel.finish() }

        try channel.writeInbound(head(status))
        try channel.writeInbound(HTTPClientResponsePart.end(nil))

        try channel.throwIfErrorCaught()

        guard case .head = try channel.readInbound(as: HTTPClientResponsePart.self) else {
            Issue.record("expected the head")
            return
        }

        guard case .end = try channel.readInbound(as: HTTPClientResponsePart.self) else {
            Issue.record("expected the end")
            return
        }
    }

    @Test
    func aMessageWithOnlyEmptyBodyParts_endsWithoutAnError() throws {
        let channel = try channel(installing: true)
        defer { _ = try? channel.finish() }

        try channel.writeInbound(head(.movedPermanently))
        try channel.writeInbound(body([]))
        try channel.writeInbound(HTTPClientResponsePart.end(nil))

        try channel.throwIfErrorCaught()
    }

    // MARK: - What is still an error

    @Test
    func aBodyCutShort_isStillReportedAsTruncated() throws {
        let channel = try channel(installing: true)
        defer { _ = try? channel.finish() }

        try channel.writeInbound(head(.ok))
        try channel.writeInbound(body(Array(Self.gzipHello.prefix(5))))
        // `EmbeddedChannel` throws what was caught from the write that caused it.
        #expect(throws: NIOHTTPDecompression.ExtraDecompressionError.truncatedData) {
            try channel.writeInbound(HTTPClientResponsePart.end(nil))
            try channel.throwIfErrorCaught()
        }
    }

    @Test
    func anotherError_goesThrough() throws {
        let channel = try channel(installing: true)
        defer { _ = try? channel.finish() }

        struct Unrelated: Error, Equatable {}

        channel.pipeline.fireErrorCaught(Unrelated())

        #expect(throws: Unrelated()) {
            try channel.throwIfErrorCaught()
        }
    }

    // MARK: - One message after another

    /// What a message carried is forgotten at the next head: on a kept-alive connection, a whole
    /// body before does not excuse the next message's truncation, nor the other way round.
    @Test
    func aBodyCutShortAfterAnEmptyMessage_isStillReportedAsTruncated() throws {
        let channel = try channel(installing: true)
        defer { _ = try? channel.finish() }

        try channel.writeInbound(head(.movedPermanently))
        try channel.writeInbound(HTTPClientResponsePart.end(nil))
        try channel.throwIfErrorCaught()

        try channel.writeInbound(head(.ok))
        try channel.writeInbound(body(Array(Self.gzipHello.prefix(5))))
        // `EmbeddedChannel` throws what was caught from the write that caused it.
        #expect(throws: NIOHTTPDecompression.ExtraDecompressionError.truncatedData) {
            try channel.writeInbound(HTTPClientResponsePart.end(nil))
            try channel.throwIfErrorCaught()
        }
    }

    @Test
    func anEmptyMessageAfterAWholeBody_endsWithoutAnError() throws {
        let channel = try channel(installing: true)
        defer { _ = try? channel.finish() }

        try channel.writeInbound(head(.ok))
        try channel.writeInbound(body(Self.gzipHello))
        try channel.writeInbound(HTTPClientResponsePart.end(nil))
        try channel.throwIfErrorCaught()

        try channel.writeInbound(head(.movedPermanently))
        try channel.writeInbound(HTTPClientResponsePart.end(nil))
        try channel.throwIfErrorCaught()
    }

    @Test
    func aWholeBody_isStillDecoded() throws {
        let channel = try channel(installing: true)
        defer { _ = try? channel.finish() }

        try channel.writeInbound(head(.ok))
        try channel.writeInbound(body(Self.gzipHello))
        try channel.writeInbound(HTTPClientResponsePart.end(nil))
        try channel.throwIfErrorCaught()

        var decoded: [UInt8] = []

        while let part = try channel.readInbound(as: HTTPClientResponsePart.self) {
            if case .body(let buffer) = part {
                decoded += buffer.readableBytesView
            }
        }

        #expect(String(decoding: decoded, as: UTF8.self) == "hello")
    }

    // MARK: - Where it goes

    /// On the connection for HTTP/1.1 and on every stream for HTTP/2: the decompressor is in the
    /// stream's pipeline there, and the connection's initializer never runs for an `h2` one.
    @Test
    func aClientThatDecompresses_installsItOnEveryPipelineWithADecompressor() throws {
        var configuration = Internals.Session.Configuration()
        configuration.decompression = .enabled(
            algorithms: [InternalsDecompressionTests.MockGzipAlgorithm()],
            limit: .none
        )

        let client = try configuration.build().httpClientConfiguration

        #expect(client.http1_1ConnectionDebugInitializer != nil)
        #expect(client.http2StreamChannelDebugInitializer != nil)
    }

    @Test
    func aClientThatDoesNotDecompress_installsNothing() throws {
        let client = try Internals.Session.Configuration().build().httpClientConfiguration

        #expect(client.http1_1ConnectionDebugInitializer == nil)
        #expect(client.http2StreamChannelDebugInitializer == nil)
    }

    @Test
    func aPipelineWithNoDecompressor_isLeftAlone() throws {
        let channel = EmbeddedChannel()
        defer { _ = try? channel.finish() }

        try Internals.NothingToDecode.install(on: channel).wait()

        #expect(throws: (any Error).self) {
            try channel.pipeline.syncOperations.handler(type: Internals.NothingToDecode.InputObserver.self)
        }
    }
}

#endif
