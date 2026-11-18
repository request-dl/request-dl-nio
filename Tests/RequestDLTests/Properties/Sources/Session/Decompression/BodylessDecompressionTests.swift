//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A response with no body can still say `Content-Encoding`: a `HEAD` answered the way its `GET`
/// would be (and a CDN does that), a `304` repeating the headers of the representation, a `204`,
/// an empty `200`. There is nothing to decode in any of them, and none of them is a failure.
///
/// Against a raw socket server, like `CustomDecompressorIntegrationTests`, so what is on the wire
/// is exactly what the test says.
struct BodylessDecompressionTests {

    private typealias Server = CustomDecompressorIntegrationTests.RawHTTPServer

    /// A codec whose end is an error unless it was given something: what a real decoder says of
    /// a stream cut short, and so of one that never started.
    private struct StrictDecompressor: Decompressor {
        var contentEncodingValue: String { "strict" }

        func callAsFunction() throws -> any DecompressorStream {
            Stream()
        }

        struct Stream: DecompressorStream {
            private var hasInput = false

            mutating func callAsFunction(decompressing bytes: [UInt8]) throws -> [UInt8] {
                hasInput = hasInput || !bytes.isEmpty
                return bytes
            }

            func finish() throws -> [UInt8] {
                guard hasInput else {
                    throw TruncatedStream()
                }

                return []
            }
        }

        struct TruncatedStream: Error {}
    }

    private enum Bodyless: CaseIterable, CustomTestStringConvertible {
        case head
        case notModified
        case noContent
        case emptyBody

        var testDescription: String {
            switch self {
            case .head: "HEAD"
            case .notModified: "304"
            case .noContent: "204"
            case .emptyBody: "200 with Content-Length: 0"
            }
        }

        var method: RequestMethod {
            self == .head ? RequestMethod(.head) : RequestMethod(.get)
        }

        func response(encoding: String) -> String {
            switch self {
            case .head:
                return
                    "HTTP/1.1 200 OK\r\nContent-Encoding: \(encoding)\r\nContent-Length: 40\r\nConnection: close\r\n\r\n"
            case .notModified:
                return "HTTP/1.1 304 Not Modified\r\nContent-Encoding: \(encoding)\r\nConnection: close\r\n\r\n"
            case .noContent:
                return "HTTP/1.1 204 No Content\r\nContent-Encoding: \(encoding)\r\nConnection: close\r\n\r\n"
            case .emptyBody:
                return
                    "HTTP/1.1 200 OK\r\nContent-Encoding: \(encoding)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            }
        }

        var status: UInt {
            switch self {
            case .head, .emptyBody: 200
            case .notModified: 304
            case .noContent: 204
            }
        }
    }

    #if canImport(NIOCore)

    /// The decompression `async-http-client` does for `.gzip` and `.deflate` runs on the head of
    /// any response that names one of them, so it has to be told there is nothing to decode.
    @Test(arguments: Bodyless.allCases, ["gzip", "deflate"])
    private func aBodylessResponseWithANativeEncoding_isNotAFailureUnderNIO(
        _ kind: Bodyless,
        _ encoding: String
    ) async throws {
        // Given
        let server = try Server()
        server.respondOnce(headers: kind.response(encoding: encoding), body: [])

        // When
        let result = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            kind.method
            Session().decompressionAlgorithms([.gzip, .deflate]).requiredExecutor(.nio)
        }
        .result()

        // Then
        #expect(result.head.status.code == kind.status)
        #expect(result.payload.isEmpty)

        // What the decompressor said of it is not an error of the transaction.
        #expect(result.metrics?.transactions.isEmpty == false)
        #expect(result.metrics?.transactions.allSatisfy { $0.error == nil } == true)
    }

    /// A redirect with an encoding and no body is followed under `.nio` too. The decompressor's
    /// complaint about it came from inside AsyncHTTPClient, before the delegate had a head to tell
    /// it apart by, and failed the redirect: it is now dropped in the pipeline, see
    /// `Internals.NothingToDecode`.
    @Test(arguments: [301, 302, 303, 307, 308])
    private func aRedirectWithAnEncodingAndNoBody_isFollowedUnderNIO(_ status: Int) async throws {
        // Given: the redirect, and where it goes, which is encoded too.
        let target = try Server()
        let body = try CustomDecompressorIntegrationTests.gzipCompressed("moved here")

        target.respondOnce(
            headers:
                "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n",
            body: body
        )

        let server = try Server()
        server.respondOnce(
            headers:
                "HTTP/1.1 \(status) Moved\r\nLocation: http://127.0.0.1:\(target.port)/moved\r\nContent-Encoding: gzip\r\nContent-Length: 0\r\nConnection: close\r\n\r\n",
            body: []
        )

        // When
        let result = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Session().decompressionAlgorithms([.gzip]).requiredExecutor(.nio)
        }
        .result()

        // Then
        #expect(result.head.status.code == 200)
        #expect(String(decoding: result.payload, as: UTF8.self) == "moved here")
        #expect(target.request.hasPrefix("GET /moved "))
        #expect(result.metrics?.transactions.count == 2)
        #expect(result.metrics?.transactions.allSatisfy { $0.error == nil } == true)
    }

    /// The same over HTTP/2, where the decompressor is in each stream's pipeline and not in the
    /// connection's.
    @Test
    private func aRedirectWithAnEncodingAndNoBody_isFollowedUnderNIOOverHTTP2() async throws {
        // Given: `HTTP2LocalServer` only speaks `h2`, so a request that completes went over it.
        let server = try await HTTP2LocalServer.start { path in
            if path == "/redirect" {
                return (.movedPermanently, [("location", "/final"), ("content-encoding", "gzip")])
            }

            return (.ok, [("content-encoding", "gzip")])
        }

        let certificate = Certificates().server()

        // When
        let result: TaskResult<Data>

        do {
            result = try await DataTask {
                BaseURL(server.baseURL)
                Path("/redirect")
                Session().decompressionAlgorithms([.gzip]).requiredExecutor(.nio)

                SecureConnection {
                    TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
                }
            }
            .result()
        } catch {
            try await server.stop()
            throw error
        }

        let requests = server.requests
        try await server.stop()

        // Then
        #expect(result.head.status.code == 200)
        #expect(requests.map(\.path) == ["/redirect", "/final"])
        #expect(result.metrics?.transactions.allSatisfy { $0.error == nil } == true)
    }

    /// A redirect whose encoded body is cut short is still a failure: what is dropped is a
    /// complaint about nothing, not about something that was there.
    @Test
    private func aRedirectWithATruncatedEncodedBody_isStillAFailureUnderNIO() async throws {
        // Given: where it goes answers, so only the truncation can fail the request.
        let target = try Server()
        target.respondOnce(
            headers: "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n",
            body: Array("ok".utf8)
        )

        let complete = try CustomDecompressorIntegrationTests.gzipCompressed(String(repeating: "moved ", count: 100))
        let truncated = Array(complete.prefix(10))

        let server = try Server()
        server.respondOnce(
            headers:
                "HTTP/1.1 301 Moved Permanently\r\nLocation: http://127.0.0.1:\(target.port)/moved\r\nContent-Encoding: gzip\r\nContent-Length: \(truncated.count)\r\nConnection: close\r\n\r\n",
            body: truncated
        )

        // Then
        await #expect(throws: (any Error).self) {
            _ = try await DataTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Session().decompressionAlgorithms([.gzip]).requiredExecutor(.nio)
            }
            .result()
        }
    }

    /// What is tolerated is a response that cannot have a body. One that has one, and whose stream
    /// ends before it is whole, is still the failure it was.
    @Test
    private func aTruncatedBody_isStillAFailureUnderNIO() async throws {
        // Given
        let server = try Server()
        let complete = try CustomDecompressorIntegrationTests.gzipCompressed(
            String(repeating: "truncated ", count: 100)
        )
        let truncated = Array(complete.prefix(10))

        server.respondOnce(
            headers:
                "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nContent-Length: \(truncated.count)\r\nConnection: close\r\n\r\n",
            body: truncated
        )

        // Then
        await #expect(throws: (any Error).self) {
            _ = try await DataTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Session().decompressionAlgorithms([.gzip]).requiredExecutor(.nio)
            }
            .result()
        }
    }

    /// The conditional request of a revalidation is a `HEAD`, and a server answering it with the
    /// `Content-Encoding` of the representation does not make it fail: the cached response is
    /// confirmed, and the request is answered from it, with no second trip to the network.
    @Test
    private func aRevalidationAnsweredWithAnEncoding_stillConfirmsTheCache() async throws {
        // Given: a server that answers once, so whatever is not the revalidation finds nobody.
        let server = try Server()
        let url = "http://127.0.0.1:\(server.port)/resource"
        let cache = DataCache(suiteName: UUID().uuidString)

        await cache.removeAll()
        cache.memoryCapacity = 8 * 1_024 * 1_024
        cache.diskCapacity = 64 * 1_024 * 1_024

        await cache.setCachedData(
            await CachedData(
                response: ResponseHead(
                    url: URL(string: url),
                    status: .init(code: 200, reason: "Ok"),
                    version: .init(minor: 1, major: 1),
                    headers: HTTPHeaders([
                        ("ETag", "\"cached\""),
                        ("Cache-Control", "public, max-age=3600"),
                        ("Content-Length", "6"),
                    ]),
                    isKeepAlive: false
                ),
                policy: .all,
                data: Data("cached".utf8)
            ),
            forKey: url
        )

        server.respondOnce(
            headers:
                "HTTP/1.1 304 Not Modified\r\nContent-Encoding: gzip\r\nETag: \"cached\"\r\nConnection: close\r\n\r\n",
            body: []
        )

        // When
        let result = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path("/resource")
            Session()
                .decompressionAlgorithms([.gzip])
                .requiredExecutor(.nio)
                .cachePolicy(.all)
                .cacheStrategy(.reloadAndValidateCachedData)
                .cache(memoryCapacity: 0, diskCapacity: 0, url: cache.directoryURL)
        }
        .result()

        // Then
        #expect(String(decoding: result.payload, as: UTF8.self) == "cached")
        #expect(result.metrics?.transactions.map(\.source) == [.revalidation, .cache])
    }

    #endif

    /// A decoder that this package runs itself (no executor decodes it natively) is not asked to
    /// finish a stream it was never given a byte of, on any executor: there is no stream.
    @Test(arguments: Bodyless.allCases, TransferTestExecutor.allCases)
    private func aBodylessResponseWithACustomEncoding_isNotAskedToDecodeAnything(
        _ kind: Bodyless,
        _ executor: TransferTestExecutor
    ) async throws {
        // Given
        let server = try Server()
        server.respondOnce(headers: kind.response(encoding: "strict"), body: [])

        // When
        let result = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            kind.method
            executor.pinnedSession.decompressionAlgorithms([.gzip, StrictDecompressor()])
        }
        .result()

        // Then
        #expect(result.head.status.code == kind.status)
        #expect(result.payload.isEmpty)
    }
}
