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

/// `URLOverride` on the hops of a redirect, end to end through the public API, on both executors.
///
/// The first request is rewritten when it is resolved, but a redirect is followed by the executor
/// and never resolved again, so a response that sends the client back to the host an override
/// stands in for used to reach the real one. Here `staging.example.test` (a name that resolves to
/// nothing) stands in for a `LocalServer`: a hop that is not rewritten does not arrive anywhere.
///
/// Two `LocalServer`s on different ports are two different origins, and both answer with what they
/// received (`receivedCookieHeader`), so a test proves what reached the wire, not what the client
/// meant to send.
struct URLOverrideRedirectTests {

    // MARK: - Inner types

    enum Executor: String, Sendable, CustomTestStringConvertible {
        #if canImport(Darwin)
        case urlSession
        #endif
        #if canImport(NIOCore)
        case nio
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
        return executors
    }()

    static let staging = "staging.example.test"
    static let elsewhere = "elsewhere.example.test"

    // MARK: - Tests

    /// The case the override exists for: the response sends the client back to the host the
    /// override stands in for, and it has to land on the override's destination again, with the
    /// credentials of the origin it is still talking to.
    @Test(arguments: executors, [Mode.follow, .strategy])
    func dataTask_whenRedirectedBackToTheOverriddenHost_followsTheOverride(
        executor: Executor,
        mode: Mode
    ) async throws {
        // Given
        let origin = try await LocalServer(.init(host: "localhost", port: 8941, option: .none))

        let originPath = "/" + UUID().uuidString
        let nextPath = "/" + UUID().uuidString

        origin.cleanup(at: originPath)
        origin.cleanup(at: nextPath)
        defer {
            origin.cleanup(at: originPath)
            origin.cleanup(at: nextPath)
        }

        origin.insert(
            LocalServer.ResponseConfiguration(
                status: .found,
                headers: ["Location": "https://\(Self.staging)\(nextPath)"],
                data: Data()
            ),
            at: originPath
        )
        origin.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: nextPath)

        // When
        let data = try await DataTask {
            BaseURL(Self.staging)
            Path(originPath)
            CustomHeader(name: "Cookie", value: "session=abc")

            URLOverride("https://\(origin.baseURL)", from: "https://\(Self.staging)")

            mode.apply(to: executor.apply(to: .localServer))

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then: it got there, and, the rewritten hop being on the origin the request was sent to,
        // the cookie went along, exactly as it does for a redirect that never left that origin.
        #expect(result.response == "reached")
        #expect(result.receivedCookieHeader == "session=abc")
    }

    /// A redirect to a host no rule covers is followed as the server wrote it, and it is another
    /// origin, so what belongs to the first one stays behind. The override changes neither.
    @Test(arguments: executors, [Mode.follow, .strategy])
    func dataTask_whenRedirectedToAHostNoRuleCovers_followsItUntouchedAndStripsTheCookie(
        executor: Executor,
        mode: Mode
    ) async throws {
        // Given
        let origin = try await LocalServer(.init(host: "localhost", port: 8941, option: .none))
        let destination = try await LocalServer(.init(host: "localhost", port: 8942, option: .none))

        let originPath = "/" + UUID().uuidString
        let destinationPath = "/" + UUID().uuidString

        origin.cleanup(at: originPath)
        destination.cleanup(at: destinationPath)
        defer {
            origin.cleanup(at: originPath)
            destination.cleanup(at: destinationPath)
        }

        origin.insert(
            LocalServer.ResponseConfiguration(
                status: .found,
                headers: ["Location": "https://\(destination.baseURL)\(destinationPath)"],
                data: Data()
            ),
            at: originPath
        )
        destination.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: destinationPath)

        // When
        let data = try await DataTask {
            BaseURL(Self.staging)
            Path(originPath)
            CustomHeader(name: "Cookie", value: "session=abc")

            URLOverride("https://\(origin.baseURL)", from: "https://\(Self.staging)")

            mode.apply(to: executor.apply(to: .localServer))

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == "reached")
        #expect(result.receivedCookieHeader == nil)
    }

    /// Two hosts overridden to two different servers: the hop is rewritten to the second one, and
    /// since that is another origin than the one the request was sent to, the cookie of the first
    /// does not follow, the same as for any other redirect to another origin. The override does
    /// not make the origin check look at the host the server wrote.
    @Test(arguments: executors, [Mode.follow, .strategy])
    func dataTask_whenRedirectedToAnotherOverriddenHost_followsItsOverrideAndStripsTheCookie(
        executor: Executor,
        mode: Mode
    ) async throws {
        // Given
        let origin = try await LocalServer(.init(host: "localhost", port: 8941, option: .none))
        let destination = try await LocalServer(.init(host: "localhost", port: 8942, option: .none))

        let originPath = "/" + UUID().uuidString
        let destinationPath = "/" + UUID().uuidString

        origin.cleanup(at: originPath)
        destination.cleanup(at: destinationPath)
        defer {
            origin.cleanup(at: originPath)
            destination.cleanup(at: destinationPath)
        }

        origin.insert(
            LocalServer.ResponseConfiguration(
                status: .found,
                headers: ["Location": "https://\(Self.elsewhere)\(destinationPath)"],
                data: Data()
            ),
            at: originPath
        )
        destination.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: destinationPath)

        // When
        let data = try await DataTask {
            BaseURL(Self.staging)
            Path(originPath)
            CustomHeader(name: "Cookie", value: "session=abc")

            URLOverride([
                "https://\(Self.staging)": "https://\(origin.baseURL)",
                "https://\(Self.elsewhere)": "https://\(destination.baseURL)",
            ])

            mode.apply(to: executor.apply(to: .localServer))

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == "reached")
        #expect(result.receivedCookieHeader == nil)
    }

    /// The request itself is to a host no rule covers, and the response sends it to one that is:
    /// every hop is checked against the rules, not only the ones that follow a rewritten request.
    @Test(arguments: executors, [Mode.follow, .strategy])
    func dataTask_whenAnUnrewrittenRequestIsRedirectedToAnOverriddenHost_followsTheOverride(
        executor: Executor,
        mode: Mode
    ) async throws {
        // Given
        let origin = try await LocalServer(.init(host: "localhost", port: 8941, option: .none))
        let destination = try await LocalServer(.init(host: "localhost", port: 8942, option: .none))

        let originPath = "/" + UUID().uuidString
        let destinationPath = "/" + UUID().uuidString

        origin.cleanup(at: originPath)
        destination.cleanup(at: destinationPath)
        defer {
            origin.cleanup(at: originPath)
            destination.cleanup(at: destinationPath)
        }

        origin.insert(
            LocalServer.ResponseConfiguration(
                status: .found,
                headers: ["Location": "https://\(Self.staging)\(destinationPath)"],
                data: Data()
            ),
            at: originPath
        )
        destination.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: destinationPath)

        // When: `origin` is not an origin of any rule; `staging` is.
        let data = try await DataTask {
            BaseURL(origin.baseURL)
            Path(originPath)

            URLOverride("https://\(destination.baseURL)", from: "https://\(Self.staging)")

            mode.apply(to: executor.apply(to: .localServer))

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == "reached")
    }

    /// A rule scoped to a path prefix replaces that prefix on a hop the way it does on the request.
    @Test(arguments: executors, [Mode.follow, .strategy])
    func dataTask_whenRedirectedBackToAPathScopedOverride_replacesTheMatchedPrefix(
        executor: Executor,
        mode: Mode
    ) async throws {
        // Given
        let origin = try await LocalServer(.init(host: "localhost", port: 8941, option: .none))

        let first = UUID().uuidString
        let next = UUID().uuidString

        origin.cleanup(at: "/v2/\(first)")
        origin.cleanup(at: "/v2/\(next)")
        defer {
            origin.cleanup(at: "/v2/\(first)")
            origin.cleanup(at: "/v2/\(next)")
        }

        origin.insert(
            LocalServer.ResponseConfiguration(
                status: .found,
                headers: ["Location": "https://\(Self.staging)/api/\(next)"],
                data: Data()
            ),
            at: "/v2/\(first)"
        )
        origin.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: "/v2/\(next)")

        // When
        let data = try await DataTask {
            BaseURL(Self.staging)
            Path("api/\(first)")

            URLOverride("https://\(origin.baseURL)/v2", from: "https://\(Self.staging)/api")

            mode.apply(to: executor.apply(to: .localServer))

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == "reached")
    }

    /// The request went to a server no rule covers (`/v1`), carrying credentials, and the response
    /// sends it to another path of that same server, which a path-scoped rule maps to a different
    /// server. The `Location` is on the origin the request already went to, so the executor keeps
    /// every credential; the destination is another origin, and none of them may get there.
    @Test(arguments: executors, [Mode.follow, .strategy])
    func dataTask_whenASameOriginLocationIsMappedToAnotherOrigin_stripsTheCredentials(
        executor: Executor,
        mode: Mode
    ) async throws {
        // Given
        let origin = try await LocalServer(.init(host: "localhost", port: 8941, option: .none))
        let destination = try await LocalServer(.init(host: "localhost", port: 8942, option: .none))

        let first = UUID().uuidString
        let next = UUID().uuidString

        origin.cleanup(at: "/v1/\(first)")
        destination.cleanup(at: "/\(next)")
        defer {
            origin.cleanup(at: "/v1/\(first)")
            destination.cleanup(at: "/\(next)")
        }

        origin.insert(
            LocalServer.ResponseConfiguration(
                status: .found,
                headers: ["Location": "https://\(origin.baseURL)/v2/\(next)"],
                data: Data()
            ),
            at: "/v1/\(first)"
        )
        destination.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: "/\(next)")

        // When: `/v2` of the origin is the only part a rule covers.
        let data = try await DataTask {
            BaseURL(origin.baseURL)
            Path("v1/\(first)")
            CustomHeader(name: "Cookie", value: "session=abc")

            URLOverride("https://\(destination.baseURL)", from: "https://\(origin.baseURL)/v2")

            mode.apply(to: executor.apply(to: .localServer))

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == "reached")
        #expect(result.receivedCookieHeader == nil)
    }

    /// A relative `Location` is resolved against the host the request was actually sent to, so it
    /// needs no rule, and the rules have nothing to say about it.
    @Test(arguments: executors, [Mode.follow, .strategy])
    func dataTask_whenRedirectedWithARelativeLocation_staysOnTheEffectiveHost(
        executor: Executor,
        mode: Mode
    ) async throws {
        // Given
        let origin = try await LocalServer(.init(host: "localhost", port: 8941, option: .none))

        let originPath = "/" + UUID().uuidString
        let nextPath = "/" + UUID().uuidString

        origin.cleanup(at: originPath)
        origin.cleanup(at: nextPath)
        defer {
            origin.cleanup(at: originPath)
            origin.cleanup(at: nextPath)
        }

        origin.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": nextPath], data: Data()),
            at: originPath
        )
        origin.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: nextPath)

        // When
        let data = try await DataTask {
            BaseURL(Self.staging)
            Path(originPath)
            CustomHeader(name: "Cookie", value: "session=abc")

            URLOverride("https://\(origin.baseURL)", from: "https://\(Self.staging)")

            mode.apply(to: executor.apply(to: .localServer))

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == "reached")
        #expect(result.receivedCookieHeader == "session=abc")
    }

    /// What a `RedirectStrategy` is handed is the request that would be sent, which is what the
    /// history it is given records of every earlier hop, not the host the override stands in for.
    @Test(arguments: executors)
    func dataTask_whenAStrategyIsConsulted_theCandidateIsAlreadyRewritten(executor: Executor) async throws {
        // Given
        let origin = try await LocalServer(.init(host: "localhost", port: 8941, option: .none))

        let originPath = "/" + UUID().uuidString
        let nextPath = "/" + UUID().uuidString

        origin.cleanup(at: originPath)
        origin.cleanup(at: nextPath)
        defer {
            origin.cleanup(at: originPath)
            origin.cleanup(at: nextPath)
        }

        origin.insert(
            LocalServer.ResponseConfiguration(
                status: .found,
                headers: ["Location": "https://\(Self.staging)\(nextPath)"],
                data: Data()
            ),
            at: originPath
        )
        origin.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: nextPath)

        let seenURL = LockedValueBox<String?>(nil)

        // When
        let data = try await DataTask {
            BaseURL(Self.staging)
            Path(originPath)

            URLOverride("https://\(origin.baseURL)", from: "https://\(Self.staging)")

            executor.apply(to: .localServer)
                .onRedirect { context in
                    seenURL.withLockedValue { $0 = context.redirectRequest.url }
                    return .follow(context.redirectRequest)
                }

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == "reached")
        #expect(seenURL.withLockedValue { $0 } == "https://\(origin.baseURL)\(nextPath)")
    }
}
