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

/// What a redirect to another origin is allowed to carry along, end to end through the public API,
/// on both executors.
///
/// Two `LocalServer`s on different ports are two different origins. Both answer with what they
/// received (`receivedCookieHeader`, `receivedHostHeader`), so a test proves what reached the wire,
/// not what the client meant to send.
struct RedirectCrossOriginHeadersTests {

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

    // MARK: - Tests

    /// `Host` picks the virtual host at the origin a request was addressed to. Replayed on a
    /// redirect to another origin it would route the request to whatever virtual host of the new
    /// server answers to that name: behind a shared CDN or proxy, possibly somebody else's.
    @Test(arguments: executors, [Mode.follow, .strategy])
    func dataTask_whenRedirectedToAnotherOrigin_doesNotForwardTheExplicitHostHeader(
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
            BaseURL(origin.baseURL)
            Path(originPath)
            HostHeader("api.internal")

            mode.apply(to: executor.apply(to: .localServer))

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then: it got there, and it did not ask for the virtual host of the first origin.
        #expect(result.response == "reached")
        #expect(result.receivedHostHeader != nil)
        #expect(result.receivedHostHeader != "api.internal")
    }

    /// Control for the test above: the same `Host`, kept while the redirect stays on the origin it
    /// was addressed to (the one thing that makes stripping it on the other path mean something).
    ///
    /// The destination is the same origin, so it is `Host`'s own value that must come back.
    @Test(arguments: executors, [Mode.follow, .strategy])
    func dataTask_whenRedirectedWithinTheSameOrigin_keepsTheExplicitHostHeader(
        executor: Executor,
        mode: Mode
    ) async throws {
        // Given
        let origin = try await LocalServer(.init(host: "localhost", port: 8941, option: .none))

        let originPath = "/" + UUID().uuidString
        let destinationPath = "/" + UUID().uuidString

        origin.cleanup(at: originPath)
        origin.cleanup(at: destinationPath)
        defer {
            origin.cleanup(at: originPath)
            origin.cleanup(at: destinationPath)
        }

        origin.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": destinationPath], data: Data()),
            at: originPath
        )
        origin.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: destinationPath)

        // When
        let data = try await DataTask {
            BaseURL(origin.baseURL)
            Path(originPath)
            HostHeader("api.internal")

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
        #expect(result.receivedHostHeader == "api.internal")
    }

    /// The credentials are stripped from the candidate request a strategy is handed, when the
    /// redirect it came from leaves the origin. A strategy that then answers with a URL on *another*
    /// origin than the candidate's own, though, has changed where the request goes after that was
    /// checked: the candidate it started from still carries the `Cookie` of the origin it was
    /// addressed to.
    @Test(arguments: executors)
    func dataTask_whenAStrategyMovesTheRedirectToAnotherOrigin_doesNotForwardTheCookie(
        executor: Executor
    ) async throws {
        // Given: the origin redirects within itself, so the candidate keeps its `Cookie`...
        let origin = try await LocalServer(.init(host: "localhost", port: 8941, option: .none))
        let destination = try await LocalServer(.init(host: "localhost", port: 8942, option: .none))

        let originPath = "/" + UUID().uuidString
        let nextPath = "/" + UUID().uuidString
        let destinationPath = "/" + UUID().uuidString

        origin.cleanup(at: originPath)
        destination.cleanup(at: destinationPath)
        defer {
            origin.cleanup(at: originPath)
            destination.cleanup(at: destinationPath)
        }

        origin.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": nextPath], data: Data()),
            at: originPath
        )
        destination.insert(try LocalServer.ResponseConfiguration(jsonObject: "reached"), at: destinationPath)

        let target = "https://\(destination.baseURL)\(destinationPath)"
        let seenCookie = LockedValueBox<String?>(nil)

        // When: ...and the strategy sends it to the other origin, headers and all.
        let data = try await DataTask {
            BaseURL(origin.baseURL)
            Path(originPath)
            CustomHeader(name: "Cookie", value: "session=abc")

            executor.apply(to: .localServer)
                .onRedirect { context in
                    seenCookie.withLockedValue { $0 = context.redirectRequest.headers.first(name: "Cookie") }

                    var request = context.redirectRequest
                    request.url = target
                    return .follow(request)
                }

            SecureConnection {
                TrustRoots(Certificates().server().certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then: the strategy was handed the cookie (same origin), and the other origin did not get it.
        #expect(seenCookie.withLockedValue { $0 } == "session=abc")
        #expect(result.response == "reached")
        #expect(result.receivedCookieHeader == nil)
    }
}
