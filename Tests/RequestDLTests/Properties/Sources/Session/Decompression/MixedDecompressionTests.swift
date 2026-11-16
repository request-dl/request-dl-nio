//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL

#if canImport(NIOCore)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// What `.nio` announces in `Accept-Encoding` and what it then does with the `Content-Encoding`
/// that comes back, for a list that mixes the algorithms `async-http-client` decodes by itself
/// (`gzip`, `deflate`) with one this package runs.
///
/// The decompressor that does the first half is part of the client's pipeline, and decides from the
/// first token of `Content-Encoding` alone and with no regard for which algorithms were asked for,
/// so what is announced and what is left to this package have to be settled around it.
struct MixedDecompressionTests {

    private typealias Server = CustomDecompressorIntegrationTests.RawHTTPServer

    /// A codec that does nothing to the bytes: what is under test is which encodings reach it.
    private struct TagDecompressor: Decompressor {
        var contentEncodingValue: String { "tag" }

        func callAsFunction() throws -> any DecompressorStream {
            Stream()
        }

        struct Stream: DecompressorStream {
            mutating func callAsFunction(decompressing bytes: [UInt8]) throws -> [UInt8] {
                bytes
            }

            func finish() throws -> [UInt8] {
                []
            }
        }
    }

    private static func deflateCompressed(_ string: String) throws -> [UInt8] {
        let compressor: any Compressor = DeflateAlgorithm()
        var stream = try compressor()
        var output = try stream(compressing: Array(string.utf8))
        output += try stream.finish()
        return output
    }

    private func acceptEncoding(in request: String) -> String? {
        request
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("accept-encoding:") }
            .map { String($0.dropFirst("accept-encoding:".count)).trimmingCharacters(in: .whitespaces) }
    }

    private func respond(
        with server: Server,
        encoding: String,
        body: [UInt8]
    ) {
        server.respondOnce(
            headers:
                "HTTP/1.1 200 OK\r\nContent-Encoding: \(encoding)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n",
            body: body
        )
    }

    // MARK: - What is announced

    @Test(
        arguments: [
            ([.gzip, TagDecompressor()] as [any Decompressor], "gzip, tag"),
            ([TagDecompressor()] as [any Decompressor], "tag"),
            ([.gzip] as [any Decompressor], "gzip"),
            ([.gzip, .deflate] as [any Decompressor], "gzip, deflate"),
        ]
    )
    private func theConfiguredAlgorithms_areWhatIsAnnouncedUnderNIO(
        _ algorithms: [any Decompressor],
        _ expected: String
    ) async throws {
        // Given
        let server = try Server()
        respond(with: server, encoding: "identity", body: Array("plain".utf8))

        // When
        _ = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Session().decompressionAlgorithms(algorithms).requiredExecutor(.nio)
        }
        .result()

        // Then
        #expect(acceptEncoding(in: server.request) == expected)
    }

    @Test
    private func anAcceptEncodingTheCallerSet_isNotReplacedUnderNIO() async throws {
        // Given
        let server = try Server()
        respond(with: server, encoding: "identity", body: Array("plain".utf8))

        // When
        _ = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            CustomHeader(name: "Accept-Encoding", value: "br")
            Session().decompressionAlgorithms([.gzip, TagDecompressor()]).requiredExecutor(.nio)
        }
        .result()

        // Then
        #expect(acceptEncoding(in: server.request) == "br")
    }

    // MARK: - What comes back

    /// `async-http-client` decodes `deflate` whether or not it was asked for, and decodes it
    /// before this package sees the response, which then has nothing left to do for it.
    @Test
    private func anEncodingTheNativeDecompressorTookUnasked_isDecodedOnceUnderNIO() async throws {
        // Given
        let server = try Server()
        let original = String(repeating: "deflate was not asked for. ", count: 100)
        respond(with: server, encoding: "deflate", body: try Self.deflateCompressed(original))

        // When
        let data = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Session().decompressionAlgorithms([.gzip, TagDecompressor()]).requiredExecutor(.nio)
        }
        .extractPayload()
        .result()

        // Then
        #expect(String(decoding: data, as: UTF8.self) == original)
    }

    /// The decompressor looks only at the first token, so `identity, gzip` is not decoded, and the
    /// body that is still compressed is not handed over as if it were not.
    @Test
    private func aCompressedBodyTheNativeDecompressorLeftAlone_isNotHandedOverAsPlainUnderNIO() async throws {
        // Given
        let server = try Server()
        let compressed = try CustomDecompressorIntegrationTests.gzipCompressed(
            String(repeating: "left alone. ", count: 100)
        )
        respond(with: server, encoding: "identity, gzip", body: compressed)

        // Then
        await #expect(throws: UnsupportedContentEncodingError.self) {
            _ = try await DataTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Session().decompressionAlgorithms([.gzip, TagDecompressor()]).requiredExecutor(.nio)
            }
            .extractPayload()
            .result()
        }
    }

    /// The custom algorithm still gets what is its own, next to what the native one decodes.
    @Test
    private func aCustomEncodingInTheSameList_isStillDecodedByItsAlgorithmUnderNIO() async throws {
        // Given
        let server = try Server()
        respond(with: server, encoding: "tag", body: Array("custom".utf8))

        // When
        let data = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Session().decompressionAlgorithms([.gzip, TagDecompressor()]).requiredExecutor(.nio)
        }
        .extractPayload()
        .result()

        // Then
        #expect(String(decoding: data, as: UTF8.self) == "custom")
    }
}

#endif
