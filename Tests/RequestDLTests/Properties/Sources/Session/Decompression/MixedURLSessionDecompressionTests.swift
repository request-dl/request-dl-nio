//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

#if canImport(Compression)
import Compression
#endif

/// A list that mixes natively decoded algorithms with a custom one, on `.urlSession`.
///
/// Such a list makes `.urlSession` take over `Accept-Encoding`, and it announces only the custom
/// algorithms: gzip/deflate/br are never asked for, so what CFNetwork does with them (it has been
/// seen decoding a native encoding whatever `Accept-Encoding` says) is not something these tests,
/// or the implementation, depend on. A native encoding that arrives anyway is unsolicited and fails
/// as unsupported, whether or not CFNetwork decoded it first.
///
/// Against a raw socket server, like `CustomDecompressorIntegrationTests`, so the wire is exactly
/// what each test says.
struct MixedURLSessionDecompressionTests {

    private typealias Server = CustomDecompressorIntegrationTests.RawHTTPServer

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

    /// An app's own decompressor under a name the system decodes: running it at all is the failure.
    private struct MustNotRunDecompressor: Decompressor {
        struct RanError: Error {}

        let encoding: String

        var contentEncodingValue: String { encoding }

        func callAsFunction() throws -> any DecompressorStream { throw RanError() }
    }

    /// A second custom algorithm, for the order in which they are announced.
    private struct TagDecompressor: Decompressor {
        var contentEncodingValue: String { "tag" }

        func callAsFunction() throws -> any DecompressorStream {
            RLEDecompressor.Stream()
        }
    }

    private static let original = "aaaaabbbbbbbbccccccccccccdddddddddddddeeeeeeeeeeeeeeeeeee"

    private static func rleEncode(_ string: String) -> [UInt8] {
        var output: [UInt8] = []
        let bytes = Array(string.utf8)
        var index = 0

        while index < bytes.count {
            var count = 1
            while index + count < bytes.count, bytes[index + count] == bytes[index], count < 255 {
                count += 1
            }
            output += [bytes[index], UInt8(count)]
            index += count
        }

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
        body: [UInt8],
        splitEvery size: Int? = nil
    ) {
        let headers =
            "HTTP/1.1 200 OK\r\nContent-Encoding: \(encoding)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"

        guard let size, !body.isEmpty else {
            server.respondOnce(headers: headers, body: body)
            return
        }

        let chunks = stride(from: 0, to: body.count, by: size).map { Array(body[$0..<min($0 + size, body.count)]) }
        server.respondOnce(headers: headers, chunks: chunks, interval: .milliseconds(2))
    }

    private func fetch(
        from server: Server,
        algorithms: [any Decompressor],
        method: RequestMethod = RequestMethod(.get)
    ) async throws -> Data {
        try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            method
            Session()
                .decompressionAlgorithms(algorithms)
                .requiredExecutor(.urlSession)
        }
        .extractPayload()
        .result()
    }

    /// A real body for `encoding`, so CFNetwork has nothing to reject if it decodes it.
    private static func compressed(_ string: String, as encoding: String) throws -> [UInt8] {
        switch encoding {
        case "deflate":
            let compressor: any Compressor = DeflateAlgorithm()
            var stream = try compressor()
            var output = try stream(compressing: Array(string.utf8))
            output += try stream.finish()
            return output

        #if canImport(Compression)
        case "br":
            let bytes = Array(string.utf8)
            var output = [UInt8](repeating: 0, count: bytes.count + 1_024)
            let count = compression_encode_buffer(&output, output.count, bytes, bytes.count, nil, COMPRESSION_BROTLI)
            return Array(output.prefix(count))
        #endif

        default:
            return try CustomDecompressorIntegrationTests.gzipCompressed(string)
        }
    }

    // MARK: - What is announced

    @Test(
        arguments: [
            ([.gzip, RLEDecompressor()] as [any Decompressor], "rle"),
            ([RLEDecompressor(), .deflate] as [any Decompressor], "rle"),
            ([.gzip, .deflate, .brotliURLSessionOnly, RLEDecompressor()] as [any Decompressor], "rle"),
            ([.gzip, RLEDecompressor(), TagDecompressor()] as [any Decompressor], "rle, tag"),
            ([TagDecompressor(), .gzip, RLEDecompressor()] as [any Decompressor], "tag, rle"),
        ]
    )
    func mixedList_announcesOnlyTheCustomAlgorithms(
        _ algorithms: [any Decompressor],
        _ expected: String
    ) async throws {
        let server = try Server()
        respond(with: server, encoding: "rle", body: Self.rleEncode(Self.original))

        _ = try await fetch(from: server, algorithms: algorithms)

        #expect(acceptEncoding(in: server.request) == expected)
    }

    /// `.disabled` and `.nio` leave an `Accept-Encoding` the caller wrote alone, so a mixed list does too:
    /// it only fills the header in when nothing set it. A caller that wrote `AcceptEncodingHeader` is
    /// saying what the server is to be asked for, and which executor happens to resolve must not change
    /// that.
    @Test
    func mixedList_whenTheCallerSetsAcceptEncoding_keepsItOnTheWire() async throws {
        let server = try Server()
        respond(with: server, encoding: "rle", body: Self.rleEncode(Self.original))

        let data = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            AcceptEncodingHeader(.identity)
            Session()
                .decompressionAlgorithms([.gzip, RLEDecompressor()])
                .requiredExecutor(.urlSession)
        }
        .extractPayload()
        .result()

        // As `AcceptEncodingHeader` writes it, quality value included, and not the custom algorithm's.
        #expect(acceptEncoding(in: server.request) == "identity;q=1.0")

        // And the response is still decoded by what the list says, not by what was asked for.
        #expect(String(data: data, encoding: .utf8) == Self.original)
    }

    // MARK: - What is decoded

    @Test
    func mixedList_whenServerSendsTheCustomEncoding_decodesIt() async throws {
        let server = try Server()
        respond(with: server, encoding: "rle", body: Self.rleEncode(Self.original))

        let data = try await fetch(from: server, algorithms: [.gzip, RLEDecompressor()])

        #expect(String(data: data, encoding: .utf8) == Self.original)
    }

    @Test(arguments: [1, 2, 3, 7])
    func mixedList_whenCustomBodyArrivesInSmallPieces_decodesIt(size: Int) async throws {
        let server = try Server()
        respond(with: server, encoding: "rle", body: Self.rleEncode(Self.original), splitEvery: size)

        let data = try await fetch(from: server, algorithms: [.gzip, .deflate, RLEDecompressor()])

        #expect(String(data: data, encoding: .utf8) == Self.original)
    }

    @Test
    func mixedList_whenResponseHasNoBody_isNotAFailure() async throws {
        let server = try Server()
        respond(with: server, encoding: "rle", body: [])

        let data = try await fetch(from: server, algorithms: [.gzip, RLEDecompressor()])

        #expect(data.isEmpty)
    }

    @Test
    func mixedList_whenHeadResponseSaysTheCustomEncoding_isNotAFailure() async throws {
        let server = try Server()
        server.respondOnce(
            headers: "HTTP/1.1 200 OK\r\nContent-Encoding: rle\r\nContent-Length: 40\r\nConnection: close\r\n\r\n",
            body: []
        )

        let data = try await fetch(
            from: server,
            algorithms: [.gzip, RLEDecompressor()],
            method: RequestMethod(.head)
        )

        #expect(data.isEmpty)
    }

    // MARK: - A native encoding nobody asked for

    /// Not asked for, so it matches nothing this package decodes, whether CFNetwork already
    /// decoded the body or not: there is no guessing which, and no passing bytes through on one.
    @Test(arguments: ["gzip", "deflate", "br"])
    func mixedList_whenServerSendsAnUnaskedNativeEncoding_failsAsUnsupported(encoding: String) async throws {
        let server = try Server()
        let body = try Self.compressed(String(repeating: "unasked ", count: 100), as: encoding)
        respond(with: server, encoding: encoding, body: body)

        let error = try await #require(throws: UnsupportedContentEncodingError.self) {
            _ = try await fetch(from: server, algorithms: [.gzip, .deflate, .brotliURLSessionOnly, RLEDecompressor()])
        }

        #expect(error.value == encoding)
    }

    @Test
    func mixedList_whenServerSendsTheNativeEncodingInPieces_failsAsUnsupported() async throws {
        let server = try Server()
        respond(
            with: server,
            encoding: "gzip",
            body: try Self.compressed(String(repeating: "unasked ", count: 100), as: "gzip"),
            splitEvery: 5
        )

        await #expect(throws: UnsupportedContentEncodingError.self) {
            _ = try await fetch(from: server, algorithms: [.gzip, RLEDecompressor()])
        }
    }

    // MARK: - A custom algorithm under a name the system decodes

    /// An app's own `Decompressor` for `br` (`.nio` has no brotli) is announced, and CFNetwork
    /// decodes `br` all the same and keeps the header. Dispatch ran the app's decompressor over the
    /// plain bytes a second time. The system's decoding is the one that applies, so the decompressor
    /// of the app never runs.
    @Test(arguments: ["gzip", "deflate", "br"])
    func aCustomAlgorithmForANativeName_isAnnouncedButNotRunOverWhatTheSystemDecoded(encoding: String) async throws {
        let server = try Server()
        let original = String(repeating: "decoded by the system. ", count: 100)
        respond(with: server, encoding: encoding, body: try Self.compressed(original, as: encoding))

        let data = try await fetch(from: server, algorithms: [MustNotRunDecompressor(encoding: encoding)])

        #expect(acceptEncoding(in: server.request) == encoding)
        #expect(String(data: data, encoding: .utf8) == original)
    }

    /// Only the names it announced: an unrelated native encoding is still the server's own doing.
    @Test
    func aCustomAlgorithmForANativeName_doesNotLetAnotherNativeEncodingThrough() async throws {
        let server = try Server()
        respond(
            with: server,
            encoding: "deflate",
            body: try Self.compressed(String(repeating: "unasked ", count: 100), as: "deflate")
        )

        await #expect(throws: UnsupportedContentEncodingError.self) {
            _ = try await fetch(from: server, algorithms: [MustNotRunDecompressor(encoding: "br")])
        }
    }

    // MARK: - Unchanged

    @Test
    func nativeOnlyList_stillLeavesDecodingToTheSystem() async throws {
        let server = try Server()
        let original = String(repeating: "native only, left to the system. ", count: 100)
        respond(with: server, encoding: "gzip", body: try Self.compressed(original, as: "gzip"))

        let data = try await fetch(from: server, algorithms: [.gzip, .deflate])

        #expect(String(data: data, encoding: .utf8) == original)
    }

    @Test
    func disabledDecompression_stillAsksForIdentity() async throws {
        let server = try Server()
        respond(with: server, encoding: "identity", body: Array("plain".utf8))

        let data = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Session().disableDecompression().requiredExecutor(.urlSession)
        }
        .extractPayload()
        .result()

        #expect(String(data: data, encoding: .utf8) == "plain")
        #expect(acceptEncoding(in: server.request) == "identity")
    }
}

#endif
