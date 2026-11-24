//
// See LICENSE for this package's licensing information.
//

import Foundation
import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

/// A cookie with a non-ASCII value never gets into the jar, so what one executor puts in cannot cost
/// the other the cookies after it: `URLSession` sends Latin-1 and cuts the whole `Cookie` header at
/// the first character it cannot encode, which used to turn `a=ok; b=日本語; c=after` into `a=ok; b=`.
struct CookieJarNonASCIITests {

    typealias Executor = CookieJarTests.Executor

    static let executors = CookieJarTests.executors

    private static func cookie(_ name: String, value: String) -> CookieJar.Cookie {
        CookieJar.Cookie(name: name, value: value, domain: "localhost", expires: Date(timeIntervalSinceNow: 3_600))
    }

    @Test
    func insert_whenValueOrNameIsNotASCII_isRefused() {
        let jar = CookieJar()

        #expect(throws: CookieJarError.invalidValue) {
            try jar.insert(Self.cookie("b", value: "日本語"))
        }

        #expect(throws: CookieJarError.invalidValue) {
            try jar.insert(Self.cookie("b", value: "José"))
        }

        #expect(throws: CookieJarError.invalidName) {
            try jar.insert(Self.cookie("naïve", value: "1"))
        }

        #expect(jar.cookies.isEmpty)
    }

    @Test(arguments: executors)
    func dataTask_whenAResponseSetsANonASCIICookie_theOthersStillReachTheServer(executor: Executor) async throws {
        // Given
        let server = try await LocalServer(.init(host: "localhost", port: 8962, option: .none))
        let (setPath, echoPath) = ("/" + UUID().uuidString, "/" + UUID().uuidString)
        defer { [setPath, echoPath].forEach(server.cleanup(at:)) }

        server.insert(
            .init(
                headers: .init([("Set-Cookie", "a=ok"), ("Set-Cookie", "b=日本語"), ("Set-Cookie", "c=after")]),
                data: Data("\"set\"".utf8)
            ),
            at: setPath
        )
        server.insert(try .init(jsonObject: "echo"), at: echoPath)

        let jar = CookieJar()

        func get(_ path: String) async throws -> HTTPResult<String> {
            let data = try await DataTask {
                BaseURL(server.baseURL)
                Path(path)
                executor.apply(to: .localServer).cookieJar(jar)
                SecureConnection {
                    TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
                }
            }
            .extractPayload()
            .result()

            return try HTTPResult<String>(data)
        }

        // When
        _ = try await get(setPath)
        let result = try await get(echoPath)

        // Then
        #expect(result.receivedCookieHeader == "a=ok; c=after")
    }
}
