//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
#endif

/// `Session.cookieJar(_:)` end to end through the public API, on every executor.
///
/// Both `LocalServer`s answer with what they received (`receivedCookieHeader`), so a test proves
/// what reached the wire, not what the client meant to send. Both live on `localhost`, and
/// cookies ignore the port, so every test makes its own jar: a cookie one test stored can never be
/// the one another is looking for.
struct CookieJarTests {

    // MARK: - Inner types

    enum Executor: String, Sendable, CustomTestStringConvertible {
        #if canImport(Darwin)
        case urlSession
        #endif
        #if canImport(NIOCore)
        case nio
        #endif
        #if canImport(NIOCore) && canImport(Darwin)
        case nioTransportServices
        #endif

        var testDescription: String { rawValue }

        func apply(to session: Session) -> Session {
            switch self {
            #if canImport(Darwin)
            case .urlSession:
                return session.requiredExecutor(.urlSession)
            #endif
            #if canImport(NIOCore)
            case .nio:
                return session.requiredExecutor(.nio)
            #endif
            #if canImport(NIOCore) && canImport(Darwin)
            case .nioTransportServices:
                return session.requiredExecutor(.nioTransportServices)
            #endif
            }
        }
    }

    /// How redirects are followed: the fixed limits, or a strategy that answers with what it was
    /// handed.
    enum Mode: String, Sendable, CustomTestStringConvertible {
        case follow
        case strategy

        var testDescription: String { rawValue }

        func apply(to session: Session) -> Session {
            switch self {
            case .follow:
                return session.enableRedirectFollow(max: 5, allowCycles: false)
            case .strategy:
                return session.onRedirect { context in .follow(context.redirectRequest) }
            }
        }
    }

    static let executors: [Executor] = {
        var executors = [Executor]()
        #if canImport(Darwin)
        executors.append(.urlSession)
        #endif
        #if canImport(NIOCore)
        executors.append(.nio)
        #endif
        #if canImport(NIOCore) && canImport(Darwin)
        executors.append(.nioTransportServices)
        #endif
        return executors
    }()

    // MARK: - Private

    private static func server(port: UInt) async throws -> LocalServer {
        try await LocalServer(.init(host: "localhost", port: port, option: .none))
    }

    private static func get(
        _ server: LocalServer,
        _ path: String,
        executor: Executor,
        mode: Mode = .follow,
        jar: CookieJar?,
        explicitCookie: String? = nil
    ) async throws -> HTTPResult<String> {
        let data = try await DataTask {
            BaseURL(server.baseURL)
            Path(path)

            if let explicitCookie {
                CustomHeader(name: "Cookie", value: explicitCookie)
            }

            let session = mode.apply(to: executor.apply(to: .localServer))
            if let jar {
                session.cookieJar(jar)
            } else {
                session
            }

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        return try HTTPResult<String>(data)
    }

    private static func setCookie(_ cookies: String...) -> LocalServer.ResponseConfiguration.Headers {
        .init(cookies.map { ("Set-Cookie", $0) })
    }

    private static func uniquePath() -> String {
        "/" + UUID().uuidString
    }

    // MARK: - Tests

    @Test(arguments: executors)
    func dataTask_whenResponseSetsACookie_sendsItOnTheNextRequest(executor: Executor) async throws {
        // Given
        let server = try await Self.server(port: 8951)
        let (setPath, echoPath) = (Self.uniquePath(), Self.uniquePath())
        defer { [setPath, echoPath].forEach(server.cleanup(at:)) }

        server.insert(.init(headers: Self.setCookie("sid=abc; Path=/", "theme=dark"), data: Data("\"set\"".utf8)), at: setPath)
        server.insert(try .init(jsonObject: "echo"), at: echoPath)

        let jar = CookieJar()

        // When
        _ = try await Self.get(server, setPath, executor: executor, jar: jar)
        let result = try await Self.get(server, echoPath, executor: executor, jar: jar)

        // Then
        #expect(result.receivedCookieHeader == "sid=abc; theme=dark")
    }

    @Test(arguments: executors)
    func dataTask_whenSessionHasNoJar_sendsNoCookies(executor: Executor) async throws {
        // Given
        let server = try await Self.server(port: 8951)
        let (setPath, echoPath) = (Self.uniquePath(), Self.uniquePath())
        defer { [setPath, echoPath].forEach(server.cleanup(at:)) }

        server.insert(.init(headers: Self.setCookie("sid=abc"), data: Data("\"set\"".utf8)), at: setPath)
        server.insert(try .init(jsonObject: "echo"), at: echoPath)

        // When
        _ = try await Self.get(server, setPath, executor: executor, jar: nil)
        let result = try await Self.get(server, echoPath, executor: executor, jar: nil)

        // Then
        #expect(result.receivedCookieHeader == nil)
    }

    @Test(arguments: executors)
    func dataTask_whenTwoJarsShareAClient_keepTheirCookiesApart(executor: Executor) async throws {
        // Given
        let server = try await Self.server(port: 8951)
        let (setPath, echoPath) = (Self.uniquePath(), Self.uniquePath())
        defer { [setPath, echoPath].forEach(server.cleanup(at:)) }

        server.insert(.init(headers: Self.setCookie("sid=abc"), data: Data("\"set\"".utf8)), at: setPath)
        // The server answers each request with the next response queued for its path.
        server.insert(try .init(jsonObject: "echo"), at: echoPath)
        server.insert(try .init(jsonObject: "echo"), at: echoPath)

        let (first, second) = (CookieJar(), CookieJar())

        // When
        _ = try await Self.get(server, setPath, executor: executor, jar: first)
        let withFirst = try await Self.get(server, echoPath, executor: executor, jar: first)
        let withSecond = try await Self.get(server, echoPath, executor: executor, jar: second)

        // Then
        #expect(withFirst.receivedCookieHeader == "sid=abc")
        #expect(withSecond.receivedCookieHeader == nil)
    }

    @Test(arguments: executors)
    func dataTask_whenRequestSetsItsOwnCookie_keepsItAndStillStoresWhatTheResponseSets(
        executor: Executor
    ) async throws {
        // Given
        let server = try await Self.server(port: 8951)
        let (setPath, echoPath) = (Self.uniquePath(), Self.uniquePath())
        defer { [setPath, echoPath].forEach(server.cleanup(at:)) }

        server.insert(.init(headers: Self.setCookie("sid=abc"), data: Data("\"set\"".utf8)), at: setPath)
        // The server answers each request with the next response queued for its path.
        server.insert(try .init(jsonObject: "echo"), at: echoPath)
        server.insert(try .init(jsonObject: "echo"), at: echoPath)

        let jar = CookieJar()

        // When
        _ = try await Self.get(server, setPath, executor: executor, jar: jar)
        let explicit = try await Self.get(server, echoPath, executor: executor, jar: jar, explicitCookie: "mine=1")
        let automatic = try await Self.get(server, echoPath, executor: executor, jar: jar)

        // Then
        #expect(explicit.receivedCookieHeader == "mine=1")
        #expect(automatic.receivedCookieHeader == "sid=abc")
    }

    @Test(arguments: executors)
    func removeAll_forgetsEveryCookie(executor: Executor) async throws {
        // Given
        let server = try await Self.server(port: 8951)
        let (setPath, echoPath) = (Self.uniquePath(), Self.uniquePath())
        defer { [setPath, echoPath].forEach(server.cleanup(at:)) }

        server.insert(.init(headers: Self.setCookie("sid=abc"), data: Data("\"set\"".utf8)), at: setPath)
        server.insert(try .init(jsonObject: "echo"), at: echoPath)

        let jar = CookieJar()
        _ = try await Self.get(server, setPath, executor: executor, jar: jar)

        // When
        jar.removeAll()
        let result = try await Self.get(server, echoPath, executor: executor, jar: jar)

        // Then
        #expect(result.receivedCookieHeader == nil)
    }

    // MARK: - Redirects

    /// A login flow: the redirect itself sets the session cookie, and the page it points to, on
    /// another origin (another port), must already receive it.
    @Test(arguments: executors, [Mode.follow, .strategy])
    func dataTask_whenARedirectSetsACookie_sendsItOnTheHopToAnotherOrigin(
        executor: Executor,
        mode: Mode
    ) async throws {
        // Given
        let origin = try await Self.server(port: 8951)
        let destination = try await Self.server(port: 8952)
        let (startPath, finalPath) = (Self.uniquePath(), Self.uniquePath())
        defer {
            origin.cleanup(at: startPath)
            destination.cleanup(at: finalPath)
        }

        origin.insert(
            .init(
                status: .found,
                headers: Self.setCookie("login=1; Path=/") + ["Location": "https://\(destination.baseURL)\(finalPath)"],
                data: Data()
            ),
            at: startPath
        )
        destination.insert(try .init(jsonObject: "reached"), at: finalPath)

        // When
        let result = try await Self.get(origin, startPath, executor: executor, mode: mode, jar: CookieJar())

        // Then
        #expect(result.response == "reached")
        #expect(result.receivedCookieHeader == "login=1")
    }

    /// Within one origin AsyncHTTPClient replays the first request's `Cookie` header on the hop,
    /// which is stale: it lacks what the redirect set.
    @Test(arguments: executors, [Mode.follow, .strategy])
    func dataTask_whenARedirectSetsACookie_sendsItOnTheHopWithinTheSameOrigin(
        executor: Executor,
        mode: Mode
    ) async throws {
        // Given
        let server = try await Self.server(port: 8951)
        let (seedPath, startPath, finalPath) = (Self.uniquePath(), Self.uniquePath(), Self.uniquePath())
        defer { [seedPath, startPath, finalPath].forEach(server.cleanup(at:)) }

        server.insert(.init(headers: Self.setCookie("old=1"), data: Data("\"seed\"".utf8)), at: seedPath)
        server.insert(
            .init(
                status: .found,
                headers: Self.setCookie("new=2") + ["Location": "https://\(server.baseURL)\(finalPath)"],
                data: Data()
            ),
            at: startPath
        )
        server.insert(try .init(jsonObject: "reached"), at: finalPath)

        let jar = CookieJar()
        _ = try await Self.get(server, seedPath, executor: executor, jar: jar)

        // When
        let result = try await Self.get(server, startPath, executor: executor, mode: mode, jar: jar)

        // Then: the stale header carried only `old`.
        #expect(result.response == "reached")
        #expect(result.receivedCookieHeader == "old=1; new=2")
    }

    /// A logout redirect deletes the cookie: the hop it leads to must not carry it any more.
    @Test(arguments: executors, [Mode.follow, .strategy])
    func dataTask_whenARedirectDeletesACookie_doesNotSendItOnTheHop(
        executor: Executor,
        mode: Mode
    ) async throws {
        // Given
        let server = try await Self.server(port: 8951)
        let (seedPath, logoutPath, finalPath) = (Self.uniquePath(), Self.uniquePath(), Self.uniquePath())
        defer { [seedPath, logoutPath, finalPath].forEach(server.cleanup(at:)) }

        server.insert(.init(headers: Self.setCookie("sid=abc"), data: Data("\"seed\"".utf8)), at: seedPath)
        server.insert(
            .init(
                status: .found,
                headers: Self.setCookie("sid=; Max-Age=0") + ["Location": "https://\(server.baseURL)\(finalPath)"],
                data: Data()
            ),
            at: logoutPath
        )
        server.insert(try .init(jsonObject: "reached"), at: finalPath)

        let jar = CookieJar()
        _ = try await Self.get(server, seedPath, executor: executor, jar: jar)

        // When
        let result = try await Self.get(server, logoutPath, executor: executor, mode: mode, jar: jar)

        // Then
        #expect(result.response == "reached")
        #expect(result.receivedCookieHeader == nil)
    }

    /// The caller set a `Cookie` header, so it is theirs on every hop, and the jar leaves it alone.
    @Test(arguments: executors)
    func dataTask_whenRequestSetsItsOwnCookie_keepsItOnTheRedirectHops(executor: Executor) async throws {
        // Given
        let server = try await Self.server(port: 8951)
        let (startPath, finalPath) = (Self.uniquePath(), Self.uniquePath())
        defer { [startPath, finalPath].forEach(server.cleanup(at:)) }

        server.insert(
            .init(
                status: .found,
                headers: Self.setCookie("new=2") + ["Location": "https://\(server.baseURL)\(finalPath)"],
                data: Data()
            ),
            at: startPath
        )
        server.insert(try .init(jsonObject: "reached"), at: finalPath)

        // When
        let result = try await Self.get(
            server, startPath, executor: executor, jar: CookieJar(), explicitCookie: "mine=1"
        )

        // Then
        #expect(result.receivedCookieHeader == "mine=1")
    }
}

private func + (
    lhs: LocalServer.ResponseConfiguration.Headers,
    rhs: LocalServer.ResponseConfiguration.Headers
) -> LocalServer.ResponseConfiguration.Headers {
    var result = lhs
    for (name, value) in rhs {
        result.add(name: name, value: value)
    }
    return result
}
