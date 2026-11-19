//
// See LICENSE for this package's licensing information.
//

@_spi(Testing) import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.URL
#endif

/// A download that lost its connection and continues is a new request, sent after the first one
/// had its answer: it has to go out with what the jar holds then, not with the `Cookie` header the
/// first request was sent with.
@Suite(.serialized)
struct CookieJarResumptionTests {

    private static let length = 8 * 1_048_576

    private static let cutAt = 1_000_000

    private typealias Executor = TransferTestExecutor

    @Test(arguments: Executor.allCases)
    private func continuation_isSentTheCookiesTheJarHoldsNow(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given: a jar with one cookie, a connection that is cut, and a wait before the
            // continuation, in which another cookie is stored.
            server.dropPlan = [Self.cutAt]

            let jar = CookieJar()
            let target = try #require(URL(string: "http://127.0.0.1:\(server.port)/resource"))
            jar.storage.store(setCookieValues: ["a=1"], for: target)

            let download = DownloadTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Path("/resource")
                executor.pinnedSession.cookieJar(jar)
            }
            .resumingDownloads(.enabled(delay: 1.5))

            // When
            async let count: Int = {
                var count = 0

                for try await chunk in try await download.result().payload {
                    count += chunk.count
                }

                return count
            }()

            try await awaitRecordedRequests(server, atLeast: 1)
            jar.storage.store(setCookieValues: ["b=2"], for: target)

            // Then
            #expect(try await count == Self.length)
            try await awaitRecordedRequests(server, atLeast: 2)

            #expect(server.requests.first?.header("Cookie") == "a=1")
            #expect(server.requests.last?.header("Cookie") == "a=1; b=2")
        }
    }
}
