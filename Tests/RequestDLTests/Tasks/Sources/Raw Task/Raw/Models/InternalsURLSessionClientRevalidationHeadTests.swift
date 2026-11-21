//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The conditional request of a cache revalidation on `.urlSession` says what the request it
/// revalidates said, the way `.nio` does (`Internals.Client+RequestExecutingClient`): a server that
/// varies on `Accept-Encoding` answers it for the same representation it sent the response in, and
/// the validator it confirms is that representation's.
///
/// Against a raw socket server, so the wire is exactly what each test reads off it.
struct InternalsURLSessionClientRevalidationHeadTests {

    private typealias Server = CustomDecompressorIntegrationTests.RawHTTPServer

    private struct CustomDecompressor: Decompressor {
        var contentEncodingValue: String { "custom" }

        func callAsFunction() throws -> any DecompressorStream {
            Stream()
        }

        struct Stream: DecompressorStream {
            mutating func callAsFunction(decompressing bytes: [UInt8]) throws -> [UInt8] { bytes }
            func finish() throws -> [UInt8] { [] }
        }
    }

    /// The `Accept-Encoding` the conditional request of a client configured for `decompression` carried.
    /// What the client is given is what `Internals.ClientManager` gives it (see
    /// `InternalsClientManagerExecutorTests`).
    private func acceptEncodingOfRevalidation(
        decompression: Internals.Decompression,
        callerValue: String? = nil
    ) async throws -> String? {
        let server = try Server()
        server.respondOnce(
            headers: "HTTP/1.1 304 Not Modified\r\nConnection: close\r\n\r\n",
            body: []
        )

        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            acceptEncoding: Internals.URLSessionClient.announcedAcceptEncoding(for: decompression)
        )

        var configuration = RequestConfiguration()
        configuration.exactURL = "http://127.0.0.1:\(server.port)/resource"
        configuration.method = "HEAD"

        if let callerValue {
            configuration.headers.add(name: "Accept-Encoding", value: callerValue)
        }

        _ = try await client.revalidationHead(configuration: configuration, logger: nil, metrics: nil)

        return server.request
            .split(separator: "\r\n")
            .first { $0.lowercased().hasPrefix("accept-encoding:") }
            .map { String($0.dropFirst("accept-encoding:".count)).trimmingCharacters(in: .whitespaces) }
    }

    private static func algorithms(_ decompressors: [any Decompressor]) -> Internals.Decompression {
        .enabled(
            algorithms: decompressors.map(InternalsDecompressionAlgorithmAdapter.init),
            limit: .none
        )
    }

    @Test
    func revalidationHead_whenDecompressionIsDisabled_asksForIdentityLikeTheRequest() async throws {
        let value = try await acceptEncodingOfRevalidation(decompression: .disabled)

        #expect(value == "identity")
    }

    @Test
    func revalidationHead_whenTheListMixesInACustomAlgorithm_announcesOnlyTheCustomOnes() async throws {
        let value = try await acceptEncodingOfRevalidation(
            decompression: Self.algorithms([GzipAlgorithm(), CustomDecompressor()])
        )

        #expect(value == "custom")
    }

    @Test
    func revalidationHead_whenTheCallerSetAcceptEncoding_keepsItLikeTheRequest() async throws {
        let value = try await acceptEncodingOfRevalidation(
            decompression: .disabled,
            callerValue: "br"
        )

        #expect(value == "br")
    }
}

#endif
