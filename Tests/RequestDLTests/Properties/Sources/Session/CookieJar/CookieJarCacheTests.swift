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

    private static let port: UInt = 8953

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
        cached: Bool = true
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
                    .cacheStrategy(.returnCachedDataElseLoad)
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
}
