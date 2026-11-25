//
// See LICENSE for this package's licensing information.
//

import Logging
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
#endif

/// A request that leaves cookies of its jar out of the `Cookie` header, because they do not fit in
/// the 8000 bytes it may have, says so in the task's logger: once, and never with a cookie in it.
struct CookieJarHeaderLimitLogTests {

    typealias Executor = CookieJarTests.Executor

    private static let port: UInt = 8957
    private static let secret = "TOP-SECRET-VALUE"

    private static func jar(bigCookies: Int) throws -> CookieJar {
        let jar = CookieJar()
        let big = String(repeating: "x", count: 4_000)

        for index in 0..<bigCookies {
            try jar.insert(CookieJar.Cookie(name: "big\(index)", value: big, domain: "localhost"))
        }

        try jar.insert(CookieJar.Cookie(name: "sid", value: secret, domain: "localhost"))
        return jar
    }

    /// The `.warning` records of `requests` requests made with `jar`.
    private static func warnings(
        requests: Int,
        jar: CookieJar,
        executor: Executor
    ) async throws -> [TestLogHandler.LogRecord] {
        let server = try await LocalServer(.init(host: "localhost", port: port, option: .none))
        let path = "/" + UUID().uuidString
        defer { server.cleanup(at: path) }

        for _ in 0..<requests {
            server.insert(try .init(jsonObject: "ok"), at: path)
        }

        let box = LockedValueBox<[TestLogHandler.LogRecord]>([])

        try await Logger.withTesting(
            level: .warning,
            recorded: { record in box.withLockedValue { $0.append(record) } },
            perform: { logger in
                for _ in 0..<requests {
                    _ = try await DataTask {
                        BaseURL(server.baseURL)
                        Path(path)
                        executor.apply(to: .localServer).cookieJar(jar)
                        SecureConnection {
                            TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
                        }
                    }
                    .extractPayload()
                    .environment(\.logger, logger)
                    .result()
                }
            }
        )

        return box.withLockedValue { $0 }.filter { String(describing: $0.message).contains("were not sent") }
    }

    @Test(arguments: CookieJarTests.executors)
    func request_whenCookiesDoNotFit_warnsOnceWithCountLimitAndHost(executor: Executor) async throws {
        // 2 of the 3 big cookies and `sid` fit; one big cookie is left out, on every request.
        let records = try await Self.warnings(requests: 3, jar: try Self.jar(bigCookies: 2), executor: executor)

        let record = try #require(records.first)
        let text = String(describing: record.message)

        #expect(records.count == 1)
        #expect(record.level == .warning)
        #expect(text.contains("1 cookie(s)"))
        #expect(text.contains("localhost"))
        #expect(text.contains("8000"))
        #expect(record.metadata["cookies_left_out"] == "1")
        #expect(record.metadata["host"] == "localhost")
        #expect(record.metadata["header_limit"] == "8000")
    }

    @Test(arguments: CookieJarTests.executors)
    func request_whenCookiesDoNotFit_neverLogsACookieNameOrValue(executor: Executor) async throws {
        let records = try await Self.warnings(requests: 1, jar: try Self.jar(bigCookies: 2), executor: executor)
        let everything = records.map { "\($0.message) \($0.metadata)" }.joined()

        #expect(!records.isEmpty)
        #expect(!everything.contains(Self.secret))
        #expect(!everything.contains("xxxx"))
        #expect(!everything.contains("sid"))
        #expect(!everything.contains("big"))
    }

    @Test(arguments: CookieJarTests.executors)
    func request_whenEverythingFits_saysNothing(executor: Executor) async throws {
        let records = try await Self.warnings(requests: 2, jar: try Self.jar(bigCookies: 1), executor: executor)

        #expect(records.isEmpty)
    }
}
