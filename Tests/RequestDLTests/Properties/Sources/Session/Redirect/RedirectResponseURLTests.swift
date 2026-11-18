//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

/// The URL a response reports is the URL that answered it: after redirects, the last one followed,
/// on every executor.
///
/// Against raw one-shot servers, each its own origin (`127.0.0.1` on another port), chained by
/// absolute `Location`s.
struct RedirectResponseURLTests {

    private typealias Server = CustomDecompressorIntegrationTests.RawHTTPServer

    private static func redirect(to url: String) -> String {
        "HTTP/1.1 307 Temporary Redirect\r\nLocation: \(url)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
    }

    private static let answer = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\n"

    @Test(arguments: TransferTestExecutor.allCases, [1, 2])
    func aRedirectedResponse_reportsTheURLThatAnsweredIt(
        _ executor: TransferTestExecutor,
        _ redirects: Int
    ) async throws {
        // Given: `redirects` servers, each sending to the next, and the last one answering.
        let final = try Server()
        final.respondOnce(headers: Self.answer, body: Array("ok".utf8))

        var servers = [final]
        var next = "http://127.0.0.1:\(final.port)/final?step=last"

        for step in 0..<redirects {
            let server = try Server()
            server.respondOnce(headers: Self.redirect(to: next), body: [])
            servers.append(server)
            next = "http://127.0.0.1:\(server.port)/hop/\(step)"
        }

        let first = try #require(servers.last)

        // When
        let result = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(first.port)")
            Path("/start")
            executor.pinnedSession
        }
        .result()

        // Then
        #expect(result.head.status.code == 200)
        #expect(result.head.url?.absoluteString == "http://127.0.0.1:\(final.port)/final?step=last")
    }

    @Test(arguments: TransferTestExecutor.allCases)
    func aResponseThatWasNotRedirected_reportsTheURLItWasSentTo(_ executor: TransferTestExecutor) async throws {
        // Given
        let server = try Server()
        server.respondOnce(headers: Self.answer, body: Array("ok".utf8))

        // When
        let result = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path("/start")
            executor.pinnedSession
        }
        .result()

        // Then
        #expect(result.head.url?.absoluteString == "http://127.0.0.1:\(server.port)/start")
    }
}
