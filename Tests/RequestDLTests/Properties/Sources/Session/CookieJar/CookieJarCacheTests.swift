//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
#endif

/// A response fetched with the cookies of one jar is never handed to a request that sends other
/// cookies, or none.
///
/// `Internals.CacheControl` treats `Cookie` as the credential a stored response was fetched with.
/// The jar's header has to be on the request before the cache looks at it, or a cookie-authenticated
/// response is stored as an anonymous one and served to every other account. The server echoes the
/// `Cookie` it received, so what each request got back shows which response it was served.
struct CookieJarCacheTests {

    typealias Executor = CookieJarTests.Executor

    private static let port: UInt = 8955

    private struct Fixture {
        let server: LocalServer
        let dataCache: DataCache
        let seedPath: String
        let resourcePath: String
        let paths: [String]
    }

    private static func makeFixture(resourceResponses: Int) async throws -> Fixture {
        let server = try await LocalServer(.init(host: "localhost", port: port, option: .none))
        let seedPath = "/" + UUID().uuidString
        let resourcePath = "/" + UUID().uuidString

        for _ in 0..<resourceResponses {
            server.insert(try .init(jsonObject: "resource"), at: resourcePath)
        }

        let dataCache = DataCache(suiteName: UUID().uuidString)
        await dataCache.removeAll()

        return Fixture(
            server: server,
            dataCache: dataCache,
            seedPath: seedPath,
            resourcePath: resourcePath,
            paths: [seedPath, resourcePath]
        )
    }

    /// A jar that holds `session=<value>` for the fixture's host.
    private static func jar(holding value: String, executor: Executor, _ fixture: Fixture) async throws -> CookieJar {
        let jar = CookieJar()
        fixture.server.insert(
            .init(
                headers: .init([("Set-Cookie", "session=\(value)")]),
                data: Data("\"seed\"".utf8)
            ),
            at: fixture.seedPath
        )

        _ = try await get(fixture.seedPath, fixture: fixture, executor: executor, jar: jar, cached: false)
        return jar
    }

    private static func get(
        _ path: String,
        fixture: Fixture,
        executor: Executor,
        jar: CookieJar?,
        cached: Bool = true,
        strategy: CacheStrategy = .returnCachedDataElseLoad
    ) async throws -> HTTPResult<String> {
        let data = try await DataTask {
            BaseURL(fixture.server.baseURL)
            Path(path)

            let base = {
                let session = executor.apply(to: .localServer)
                return jar.map(session.cookieJar) ?? session
            }()

            if cached {
                base
                    .cachePolicy(.all)
                    .cacheStrategy(strategy)
                    .cache(
                        memoryCapacity: 8 * 1_024 * 1_024,
                        diskCapacity: 8 * 1_024 * 1_024,
                        url: fixture.dataCache.directoryURL
                    )
            } else {
                base
            }

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        await fixture.dataCache.waitUntilIdle()
        return try HTTPResult<String>(data)
    }

    @Test(arguments: CookieJarTests.executors)
    func cachedResponse_isNotServedToAnotherJarOrToNoJar(executor: Executor) async throws {
        // Given: the resource is fetched by an account whose jar holds `session=a`.
        let fixture = try await Self.makeFixture(resourceResponses: 3)
        defer {
            fixture.paths.forEach(fixture.server.cleanup(at:))
        }

        let accountA = try await Self.jar(holding: "a", executor: executor, fixture)
        let accountB = try await Self.jar(holding: "b", executor: executor, fixture)

        let first = try await Self.get(fixture.resourcePath, fixture: fixture, executor: executor, jar: accountA)
        #expect(first.receivedCookieHeader == "session=a")

        // When
        let sameAccount = try await Self.get(fixture.resourcePath, fixture: fixture, executor: executor, jar: accountA)
        let otherAccount = try await Self.get(fixture.resourcePath, fixture: fixture, executor: executor, jar: accountB)
        let noJar = try await Self.get(fixture.resourcePath, fixture: fixture, executor: executor, jar: nil)

        // Then: the same account may be served what it fetched, nobody else is.
        #expect(sameAccount.receivedCookieHeader == "session=a")
        #expect(otherAccount.receivedCookieHeader == "session=b")
        #expect(noJar.receivedCookieHeader == nil)

        await fixture.dataCache.removeAll()
    }

    /// The answer to the conditional request that revalidates a stored response can renew a
    /// session: its `Set-Cookie` has to reach the jar even though it carries no body.
    @Test(arguments: CookieJarTests.executors)
    func revalidation_whenTheServerAnswers304WithACookie_storesIt(executor: Executor) async throws {
        // Given: a response stored with a validator.
        let fixture = try await Self.makeFixture(resourceResponses: 0)
        defer {
            fixture.paths.forEach(fixture.server.cleanup(at:))
        }

        fixture.server.insert(
            .init(headers: .init([("ETag", "\"v1\"")]), data: Data("\"resource\"".utf8)),
            at: fixture.resourcePath
        )

        let jar = CookieJar()
        _ = try await Self.get(fixture.resourcePath, fixture: fixture, executor: executor, jar: jar)
        #expect(jar.storage.snapshot().isEmpty)

        // When: it is revalidated, and the server confirms it and renews the session.
        fixture.server.insert(
            .init(
                status: .notModified,
                headers: .init([("ETag", "\"v1\""), ("Set-Cookie", "renewed=1")]),
                data: Data()
            ),
            at: fixture.resourcePath
        )

        _ = try await Self.get(
            fixture.resourcePath,
            fixture: fixture,
            executor: executor,
            jar: jar,
            strategy: .reloadAndValidateCachedData
        )

        // Then
        #expect(jar.storage.snapshot().map(\.name) == ["renewed"])

        await fixture.dataCache.removeAll()
    }

    /// The request goes out with no cookie, and the jar adds one on the redirect hop (the redirect
    /// itself set it): the response at the end of the chain belongs to that session, but the cache
    /// would record it as the response of a request that sent none, and give it to everyone.
    @Test(arguments: CookieJarTests.executors)
    func cachedResponse_whenARedirectHopWasSentCookies_isNotStoredForAnyone(executor: Executor) async throws {
        // Given
        let fixture = try await Self.makeFixture(resourceResponses: 0)
        let finalPath = "/" + UUID().uuidString
        defer {
            (fixture.paths + [finalPath]).forEach(fixture.server.cleanup(at:))
        }

        for session in ["login=1", "login=2"] {
            fixture.server.insert(
                .init(
                    status: .found,
                    headers: .init([
                        ("Set-Cookie", session),
                        ("Location", "https://\(fixture.server.baseURL)\(finalPath)"),
                    ]),
                    data: Data()
                ),
                at: fixture.resourcePath
            )
            fixture.server.insert(try .init(jsonObject: "account page"), at: finalPath)
        }

        // When: two sessions with their own, empty, jars ask for the same URL.
        let first = try await Self.get(fixture.resourcePath, fixture: fixture, executor: executor, jar: CookieJar())
        let second = try await Self.get(fixture.resourcePath, fixture: fixture, executor: executor, jar: CookieJar())

        // Then: the second one got its own page, not the first one's from the cache.
        #expect(first.receivedCookieHeader == "login=1")
        #expect(second.receivedCookieHeader == "login=2")

        await fixture.dataCache.removeAll()
    }
}
