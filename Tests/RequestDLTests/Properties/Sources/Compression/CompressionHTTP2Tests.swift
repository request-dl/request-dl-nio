//
// See LICENSE for this package's licensing information.
//

#if canImport(NIOCore)

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
#endif

/// `Session.compression(_:)` must compress over HTTP/2 too: splicing a `NIOHTTPRequestCompressor`
/// into the `.nio` executor's `http1_1ConnectionDebugInitializer` would silently do nothing
/// over `h2`, since HTTP/2 connections never run it (see async-http-client#917).
/// `RequestConfiguration.applyCompression()` compresses `RequestBody` itself before any
/// executor builds its request; these tests prove that over a real HTTP/2 connection.
///
/// `HTTP2LocalServer` only negotiates `h2`, so a request that completes at all went over HTTP/2.
struct CompressionHTTP2Tests {

    @Test
    func dataTask_whenGzipCompressionEnabledOverHTTP2_sendsCompressedBody() async throws {
        // Given
        let server = try await HTTP2LocalServer.start()
        let uri = "/" + UUID().uuidString
        let certificate = Certificates().server()

        // Highly compressible: a single repeated byte, so gzip shrinks it drastically.
        let payload = Data(String(repeating: "a", count: 100_000).utf8)

        let content = TestProperty {
            BaseURL(server.baseURL)
            Path(uri)

            Session("com.requestdl.tests.compression-h2.\(UUID())")
                .requiredExecutor(.nio)

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }

            Payload(data: payload)
                .compression(.gzip)
        }

        // When
        do {
            _ = try await DataTask { content }.extractPayload().result()
        } catch {
            try await server.stop()
            throw error
        }

        let requests = server.requests
        try await server.stop()

        // Then
        let request = try #require(requests.first)
        #expect(requests.count == 1)
        #expect(request.path == uri)
        #expect(request.headers.first(name: "content-encoding") == "gzip")

        // gzip's magic number, then far fewer bytes than the original payload on the wire.
        #expect(request.body.getBytes(at: request.body.readerIndex, length: 2) == [0x1f, 0x8b])
        #expect(request.body.readableBytes < payload.count / 2)

        // Framing has to describe the compressed bytes, never the original payload: a client
        // that streams the body sends no `content-length`, one that sends it must match the wire.
        if let contentLength = request.headers.first(name: "content-length") {
            #expect(Int(contentLength) == request.body.readableBytes)
        }
    }

    @Test
    func dataTask_whenCompressionDisabledOverHTTP2_sendsBodyUntouched() async throws {
        // Given
        let server = try await HTTP2LocalServer.start()
        let uri = "/" + UUID().uuidString
        let certificate = Certificates().server()
        let payload = Data(String(repeating: "a", count: 10_000).utf8)

        let content = TestProperty {
            BaseURL(server.baseURL)
            Path(uri)

            Session("com.requestdl.tests.compression-h2-off.\(UUID())")
                .requiredExecutor(.nio)

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }

            Payload(data: payload)
        }

        // When
        do {
            _ = try await DataTask { content }.extractPayload().result()
        } catch {
            try await server.stop()
            throw error
        }

        let requests = server.requests
        try await server.stop()

        // Then: the control for the test above, so a passing `gzip` assertion can't be an
        // artifact of the server itself.
        let request = try #require(requests.first)
        #expect(request.headers.first(name: "content-encoding") == nil)
        #expect(request.body.readableBytes == payload.count)
    }
}

#endif
