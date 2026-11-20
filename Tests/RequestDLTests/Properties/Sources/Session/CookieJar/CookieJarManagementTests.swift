//
// See LICENSE for this package's licensing information.
//

import Foundation
import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

/// What `CookieJar` lets a caller do to what it holds, end to end: a cookie the caller put in is
/// what reaches the wire, one the caller took out does not, and a jar that was kept and restored
/// behaves like the one it was taken from. Like `CookieJarTests`, it reads what the server
/// received, not what the client meant to send.
///
/// Every test makes its own jar and path, since every server is on `localhost` and cookies
/// ignore the port.
struct CookieJarManagementTests {

    // MARK: - Private

    typealias Executor = CookieJarTests.Executor

    static let executors = CookieJarTests.executors

    private static func server() async throws -> LocalServer {
        try await LocalServer(.init(host: "localhost", port: 8961, option: .none))
    }

    private static func get(
        _ server: LocalServer,
        _ path: String,
        executor: Executor,
        jar: CookieJar
    ) async throws -> HTTPResult<String> {
        let data = try await DataTask {
            BaseURL(server.baseURL)
            Path(path)

            executor.apply(to: .localServer)
                .cookieJar(jar)

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        return try HTTPResult<String>(data)
    }

    private static func echo(_ server: LocalServer, times: Int = 1) throws -> String {
        let path = "/" + UUID().uuidString

        for _ in 0..<times {
            server.insert(try .init(jsonObject: "echo"), at: path)
        }

        return path
    }

    private static func setCookie(_ cookies: String...) -> LocalServer.ResponseConfiguration.Headers {
        .init(cookies.map { ("Set-Cookie", $0) })
    }

    private static func cookie(
        _ name: String = "sid",
        value: String = "abc",
        hostOnly: Bool = true,
        path: String = "/",
        secure: Bool = false,
        expires: Date? = Date(timeIntervalSinceNow: 3_600)
    ) -> CookieJar.Cookie {
        CookieJar.Cookie(
            name: name,
            value: value,
            domain: "localhost",
            hostOnly: hostOnly,
            path: path,
            secure: secure,
            expires: expires
        )
    }

    // MARK: - insert

    @Test(arguments: executors)
    func insert_whenCookieIsValid_reachesTheServer(executor: Executor) async throws {
        // Given
        let server = try await Self.server()
        let path = try Self.echo(server)
        defer { server.cleanup(at: path) }

        let jar = CookieJar()
        try jar.insert(Self.cookie("a", value: "1"))
        try jar.insert(Self.cookie("b", value: "2", path: "/other"))

        // When
        let result = try await Self.get(server, path, executor: executor, jar: jar)

        // Then
        #expect(result.receivedCookieHeader == "a=1")
    }

    @Test(arguments: executors)
    func insert_whenCookieIsSecure_isSentToLoopbackAndNotToAnotherHost(executor: Executor) async throws {
        // Given
        let server = try await Self.server()
        let path = try Self.echo(server)
        defer { server.cleanup(at: path) }

        let jar = CookieJar()
        try jar.insert(Self.cookie(secure: true))

        // Then
        #expect(jar.cookies(for: URL(string: "https://elsewhere.test/")!).isEmpty)

        let result = try await Self.get(server, path, executor: executor, jar: jar)
        #expect(result.receivedCookieHeader == "sid=abc")
    }

    @Test(arguments: executors)
    func insert_whenCookieIsAlreadyExpired_isNotSent(executor: Executor) async throws {
        // Given
        let server = try await Self.server()
        let path = try Self.echo(server)
        defer { server.cleanup(at: path) }

        let jar = CookieJar()
        try jar.insert(Self.cookie())
        try jar.insert(Self.cookie(expires: Date(timeIntervalSinceNow: -10)))

        // When
        let result = try await Self.get(server, path, executor: executor, jar: jar)

        // Then
        #expect(result.receivedCookieHeader == nil)
    }

    @Test(arguments: executors)
    func insert_whenResponseSetsTheSameCookie_theResponseReplacesIt(executor: Executor) async throws {
        // Given
        let server = try await Self.server()
        let (setPath, echoPath) = ("/" + UUID().uuidString, try Self.echo(server))
        defer { [setPath, echoPath].forEach(server.cleanup(at:)) }

        server.insert(.init(headers: Self.setCookie("sid=fromServer; Path=/"), data: Data("\"set\"".utf8)), at: setPath)

        let jar = CookieJar()
        try jar.insert(Self.cookie(value: "mine"))

        // When
        _ = try await Self.get(server, setPath, executor: executor, jar: jar)
        let result = try await Self.get(server, echoPath, executor: executor, jar: jar)

        // Then
        #expect(result.receivedCookieHeader == "sid=fromServer")
        #expect(jar.cookies.count == 1)
    }

    // MARK: - remove

    @Test(arguments: executors)
    func remove_byNameDomainAndPath_stopsSendingThatCookieOnly(executor: Executor) async throws {
        // Given
        let server = try await Self.server()
        let path = try Self.echo(server)
        defer { server.cleanup(at: path) }

        let jar = CookieJar()
        try jar.insert(Self.cookie("a"))
        try jar.insert(Self.cookie("b"))

        // When
        #expect(jar.remove(name: "a", domain: "localhost", path: "/"))
        let result = try await Self.get(server, path, executor: executor, jar: jar)

        // Then
        #expect(result.receivedCookieHeader == "b=abc")
    }

    @Test(arguments: executors)
    func removeAllForHost_stopsSendingTheCookiesOfThatHost(executor: Executor) async throws {
        // Given
        let server = try await Self.server()
        let path = try Self.echo(server)
        defer { server.cleanup(at: path) }

        let jar = CookieJar()
        try jar.insert(Self.cookie("a"))
        try jar.insert(Self.cookie("b", path: "/deep"))
        try jar.insert(
            CookieJar.Cookie(
                name: "kept",
                value: "1",
                domain: "elsewhere.test",
                expires: Date(timeIntervalSinceNow: 60)
            )
        )

        // When
        jar.removeAll(forHost: "localhost")
        let result = try await Self.get(server, path, executor: executor, jar: jar)

        // Then
        #expect(result.receivedCookieHeader == nil)
        #expect(jar.cookies.map(\.name) == ["kept"])
    }

    // MARK: - Reading

    @Test(arguments: executors)
    func cookiesFor_afterAResponseSetsCookies_listsWhatTheNextRequestWouldSend(executor: Executor) async throws {
        // Given
        let server = try await Self.server()
        let setPath = "/" + UUID().uuidString
        defer { server.cleanup(at: setPath) }

        server.insert(
            .init(
                headers: Self.setCookie("sid=abc; Path=/; HttpOnly", "pref=dark; Path=/deep; Max-Age=3600"),
                data: Data("\"set\"".utf8)
            ),
            at: setPath
        )

        let jar = CookieJar()

        // When
        _ = try await Self.get(server, setPath, executor: executor, jar: jar)
        let cookies = jar.cookies(for: URL(string: "http://localhost/deep/page")!)

        // Then
        #expect(cookies.map(\.name) == ["pref", "sid"])
        #expect(cookies.map(\.value) == ["dark", "abc"])
        #expect(cookies.map(\.httpOnly) == [false, true])
        #expect(cookies.allSatisfy { $0.hostOnly && $0.domain == "localhost" })
        #expect(cookies.map { $0.expires != nil } == [true, false])
    }

    // MARK: - Persistence

    @Test(arguments: executors)
    func restore_withASnapshotOfAnotherJar_sendsItsCookies(executor: Executor) async throws {
        // Given
        let server = try await Self.server()
        let (setPath, echoPath) = ("/" + UUID().uuidString, try Self.echo(server))
        defer { [setPath, echoPath].forEach(server.cleanup(at:)) }

        server.insert(
            .init(headers: Self.setCookie("sid=abc; Max-Age=3600", "tab=1"), data: Data("\"set\"".utf8)),
            at: setPath
        )

        let original = CookieJar()
        _ = try await Self.get(server, setPath, executor: executor, jar: original)

        // The snapshot goes through JSON, as it would to be kept somewhere.
        let data = try JSONEncoder().encode(original.snapshot())
        let restored = CookieJar(restoring: try JSONDecoder().decode(CookieJar.Snapshot.self, from: data))

        // When
        let result = try await Self.get(server, echoPath, executor: executor, jar: restored)

        // Then: the persistent cookie came back, the session one did not.
        #expect(result.receivedCookieHeader == "sid=abc")
    }

    @Test(arguments: executors)
    func restore_withSessionCookiesIncluded_sendsThemToo(executor: Executor) async throws {
        // Given
        let server = try await Self.server()
        let (setPath, echoPath) = ("/" + UUID().uuidString, try Self.echo(server))
        defer { [setPath, echoPath].forEach(server.cleanup(at:)) }

        server.insert(
            .init(headers: Self.setCookie("sid=abc; Max-Age=3600", "tab=1"), data: Data("\"set\"".utf8)),
            at: setPath
        )

        let original = CookieJar()
        _ = try await Self.get(server, setPath, executor: executor, jar: original)

        let restored = CookieJar()
        let refused = restored.restore(original.snapshot(includingSessionCookies: true))

        // When
        let result = try await Self.get(server, echoPath, executor: executor, jar: restored)

        // Then
        #expect(refused == 0)
        #expect(result.receivedCookieHeader == "sid=abc; tab=1")
    }
}
