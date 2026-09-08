//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

/// End-to-end coverage for a genuinely custom (non-native) `Decompressor`, run against a raw
/// socket server that returns bytes exactly as configured -- not a unit test of the codec, but
/// of the manual-dispatch wiring itself: deriving `Accept-Encoding` from the configured
/// algorithm, matching the response's `Content-Encoding` against it, and decoding through
/// `Internals.AsyncResponse`'s transport-agnostic hook.
///
/// Doesn't use the shared `LocalServer` test harness: its `HTTPHandler` always re-encodes every
/// configured response body into a `{"receivedBytes": ..., "response": ...}` JSON envelope
/// (`LocalServer.HTTPHandler.responseData()`), which silently discards a non-JSON body like a
/// custom `Content-Encoding` payload -- it isn't built for raw-bytes-in, raw-bytes-out.
struct CustomDecompressorIntegrationTests {

    /// A toy run-length codec: a flat sequence of (byte, count) pairs, count in `1...255`.
    private struct RLEDecompressor: Decompressor {
        var contentEncodingValue: String { "rle" }

        func callAsFunction() throws -> any DecompressorStream {
            Stream()
        }

        struct Stream: DecompressorStream {
            private var pendingByte: UInt8?

            mutating func callAsFunction(decompressing bytes: [UInt8]) throws -> [UInt8] {
                var output: [UInt8] = []
                for byte in bytes {
                    if let pending = pendingByte {
                        output.append(contentsOf: Array(repeating: pending, count: Int(byte)))
                        pendingByte = nil
                    } else {
                        pendingByte = byte
                    }
                }
                return output
            }

            func finish() throws -> [UInt8] {
                []
            }
        }
    }

    private static func rleEncode(_ string: String) -> [UInt8] {
        var output: [UInt8] = []
        let bytes = Array(string.utf8)
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            var count = 1
            while i + count < bytes.count, bytes[i + count] == byte, count < 255 {
                count += 1
            }
            output.append(byte)
            output.append(UInt8(count))
            i += count
        }
        return output
    }

    /// A one-shot raw HTTP/1.1 server: accepts a single connection, ignores the request, and
    /// writes back exactly the bytes given -- no framework in the middle re-encoding anything.
    private final class RawHTTPServer: @unchecked Sendable {
        let port: UInt16
        private let listenSocket: Int32

        init() throws {
            let rawSocket = socket(AF_INET, SOCK_STREAM, 0)
            precondition(rawSocket >= 0, "failed to create socket")

            var reuse: Int32 = 1
            setsockopt(rawSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

            var addr = sockaddr_in()
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")
            addr.sin_port = 0

            let bindResult = withUnsafePointer(to: &addr) { rawAddr -> Int32 in
                rawAddr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(rawSocket, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            precondition(bindResult == 0, "failed to bind socket")
            precondition(listen(rawSocket, 1) == 0, "failed to listen")

            var boundAddr = sockaddr_in()
            var len = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &boundAddr) { rawAddr -> Int32 in
                rawAddr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    getsockname(rawSocket, $0, &len)
                }
            }

            listenSocket = rawSocket
            port = UInt16(bigEndian: boundAddr.sin_port)
        }

        /// Serves exactly one request/response on a background thread, then closes.
        func respondOnce(headers: String, body: [UInt8]) {
            let listenSocket = listenSocket
            Thread.detachNewThread {
                let client = accept(listenSocket, nil, nil)
                guard client >= 0 else { return }
                defer { close(client) }

                var requestBuffer = [UInt8](repeating: 0, count: 65_536)
                _ = requestBuffer.withUnsafeMutableBytes { read(client, $0.baseAddress, $0.count) }

                let head = Array(headers.utf8)
                head.withUnsafeBufferPointer { _ = write(client, $0.baseAddress, $0.count) }
                body.withUnsafeBufferPointer { _ = write(client, $0.baseAddress, $0.count) }
            }
        }

        deinit {
            close(listenSocket)
        }
    }

    @Test
    func decompressionAlgorithms_whenServerSendsMatchingCustomEncoding_decodesCorrectly() async throws {
        // Given
        let server = try RawHTTPServer()
        let original = "aaaaabbbbbbbbccccccccccccddddddddddddd"
        let encoded = Self.rleEncode(original)

        let headers = """
            HTTP/1.1 200 OK\r
            Content-Encoding: rle\r
            Content-Length: \(encoded.count)\r
            Connection: close\r
            \r

            """
        server.respondOnce(headers: headers, body: encoded)

        // When
        let data = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Session().decompressionAlgorithms([RLEDecompressor()])
        }
        .extractPayload()
        .result()

        // Then
        #expect(String(data: data, encoding: .utf8) == original)
    }

    @Test
    func decompressionAlgorithms_whenServerSendsUnconfiguredEncoding_throwsUnsupportedContentEncodingError()
        async throws
    {
        // Given
        let server = try RawHTTPServer()
        let body = Array("irrelevant".utf8)

        let headers = """
            HTTP/1.1 200 OK\r
            Content-Encoding: not-a-real-encoding\r
            Content-Length: \(body.count)\r
            Connection: close\r
            \r

            """
        server.respondOnce(headers: headers, body: body)

        // When / Then -- configuring a custom algorithm at all forces this package to take over
        // decoding for the whole request, so a server sending something that matches none of the
        // configured algorithms must fail loudly rather than hand back undecoded bytes silently.
        await #expect(throws: UnsupportedContentEncodingError.self) {
            _ = try await DataTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Session().decompressionAlgorithms([RLEDecompressor()])
            }
            .extractPayload()
            .result()
        }
    }

    /// Coverage for the real `BrotliURLSessionOnlyAlgorithm` type specifically -- not a mock --
    /// confirming `InternalsDecompressionAlgorithmAdapter`'s `algorithm is
    /// BrotliURLSessionOnlyAlgorithm` check actually fires for it, end to end through the public
    /// API: pinning `.nio` while it's configured must fail before ever touching the network,
    /// rather than only once a `br` response actually arrived.
    @Test
    func decompressionAlgorithms_whenBrotliURLSessionOnlyConfiguredAndNIORequired_throwsExecutorRequirementError()
        async throws
    {
        // Given -- a port nothing is listening on: if this reached the network at all, it would
        // fail with a connection error instead, not this one.
        await #expect(throws: ExecutorRequirementError.self) {
            _ = try await DataTask {
                BaseURL(.http, host: "127.0.0.1:1")
                Session()
                    .decompressionAlgorithms([.brotliURLSessionOnly, RLEDecompressor()])
                    .requiredExecutor(.nio)
            }
            .extractPayload()
            .result()
        }
    }
}
