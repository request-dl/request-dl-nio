//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(NIOCore)

/// What a redirect carries and does, the same on every executor, end to end through the public API.
///
/// `ScriptedServer`s are the origins (two ports are two origins) and say what reached the wire:
/// the method, the path and the headers of every request, which is what a divergence between
/// `URLSession` and AsyncHTTPClient is about.
struct RedirectExecutorParityTests {

    // MARK: - Inner types

    /// How redirects are followed: the session's own default, the fixed limits, or a strategy that
    /// answers with what it was handed.
    enum Mode: String, Sendable, CaseIterable, CustomTestStringConvertible {
        case standard
        case follow
        case strategy

        var testDescription: String { rawValue }

        func apply(to session: Session) -> Session {
            switch self {
            case .standard:
                return session
            case .follow:
                return session.enableRedirectFollow(max: 5, allowCycles: false)
            case .strategy:
                return session.onRedirect { context in .follow(context.redirectRequest) }
            }
        }
    }

    // MARK: - Tests

    /// A session that says nothing about redirects follows them with the default configuration,
    /// which is where an explicit `Host` is kept from the origin it was not addressed to. AsyncHTTPClient's
    /// own redirect handling, which a session with no configuration used to get, knows nothing of it.
    @Test(arguments: TransferTestExecutor.allCases, [Mode.standard, .follow, .strategy])
    func dataTask_whenRedirectedToAnotherOrigin_doesNotForwardTheExplicitHostHeader(
        executor: TransferTestExecutor,
        mode: Mode
    ) async throws {
        // Given
        let destination = try await ScriptedServer { _ in .ok() }
        let target = "\(destination.origin)/final"
        let origin = try await ScriptedServer { _ in .redirect(to: target) }

        // When
        let result = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(origin.port)")
            Path("/start")
            HostHeader("api.internal")

            mode.apply(to: executor.pinnedSession)
        }
        .result()

        let received = try #require(destination.requests.first)

        await origin.shutdown()
        await destination.shutdown()

        // Then
        #expect(result.head.status.code == 200)
        #expect(received.uri == "/final")
        #expect(received.header("Host") != nil)
        #expect(received.header("Host") != "api.internal")
    }

    /// `Authorization` and `Proxy-Authorization` stay with a redirect that does not leave the
    /// origin they were sent to. `URLSession` takes them off every redirect on its own.
    @Test(arguments: TransferTestExecutor.allCases, [Mode.standard, .follow, .strategy])
    func dataTask_whenRedirectedWithinTheSameOrigin_keepsTheCredentials(
        executor: TransferTestExecutor,
        mode: Mode
    ) async throws {
        // Given
        let server = try await ScriptedServer { received in
            received.uri == "/start" ? .redirect(to: "/next") : .ok()
        }

        let seenByStrategy = LockedValueBox<[String: String?]>([:])

        // When
        let result = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path("/start")
            CustomHeader(name: "Authorization", value: "Bearer secret")
            CustomHeader(name: "Proxy-Authorization", value: "Basic c2VjcmV0")

            if mode == .strategy {
                executor.pinnedSession.onRedirect { context in
                    seenByStrategy.withLockedValue {
                        $0["Authorization"] = context.redirectRequest.headers.first(name: "Authorization")
                        $0["Proxy-Authorization"] = context.redirectRequest.headers.first(name: "Proxy-Authorization")
                    }
                    return .follow(context.redirectRequest)
                }
            } else {
                mode.apply(to: executor.pinnedSession)
            }
        }
        .result()

        let requests = server.requests
        await server.shutdown()

        // Then
        #expect(result.head.status.code == 200)
        #expect(requests.map(\.uri) == ["/start", "/next"])

        let last = try #require(requests.last)
        #expect(last.header("Authorization") == "Bearer secret")
        #expect(last.header("Proxy-Authorization") == "Basic c2VjcmV0")

        if mode == .strategy {
            // What the strategy is handed is what is going to be sent, not what the system left.
            #expect(seenByStrategy.withLockedValue { $0["Authorization"] } == "Bearer secret")
            #expect(seenByStrategy.withLockedValue { $0["Proxy-Authorization"] } == "Basic c2VjcmV0")
        }
    }

    /// Control for the test above: what the redirect keeps within its origin it still drops on the
    /// way to another one.
    @Test(arguments: TransferTestExecutor.allCases, [Mode.standard, .follow, .strategy])
    func dataTask_whenRedirectedToAnotherOrigin_doesNotForwardTheCredentials(
        executor: TransferTestExecutor,
        mode: Mode
    ) async throws {
        // Given
        let destination = try await ScriptedServer { _ in .ok() }
        let target = "\(destination.origin)/final"
        let origin = try await ScriptedServer { _ in .redirect(to: target) }

        // When
        _ = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(origin.port)")
            Path("/start")
            CustomHeader(name: "Authorization", value: "Bearer secret")
            CustomHeader(name: "Proxy-Authorization", value: "Basic c2VjcmV0")

            mode.apply(to: executor.pinnedSession)
        }
        .result()

        let received = try #require(destination.requests.first)

        await origin.shutdown()
        await destination.shutdown()

        // Then
        #expect(received.header("Authorization") == nil)
        #expect(received.header("Proxy-Authorization") == nil)
    }

    /// A `303` asks for the target with `GET` or `HEAD` (RFC 9110, 15.4.4). A `HEAD` that is sent
    /// back as `GET` downloads a body nobody asked for, and AsyncHTTPClient keeps `HEAD`.
    @Test(
        arguments: TransferTestExecutor.allCases,
        [("HEAD", "HEAD"), ("POST", "GET")]
    )
    func dataTask_whenAnswered303_requestsTheTargetTheWayTheRFCAsks(
        executor: TransferTestExecutor,
        methods: (original: String, redirected: String)
    ) async throws {
        // Given
        let server = try await ScriptedServer { received in
            received.uri == "/start" ? .redirect(303, to: "/next") : .ok()
        }

        // When
        _ = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path("/start")
            RequestMethod(methods.original == "HEAD" ? .head : .post)

            executor.pinnedSession
        }
        .result()

        let requests = server.requests
        await server.shutdown()

        // Then
        #expect(requests.map(\.method) == [methods.original, methods.redirected])
    }

    /// `.urlSession` stops a chain at 20 redirects on its own, whatever `max` is: what it fails
    /// with is the limit being reached, not the system's error.
    @Test(arguments: TransferTestExecutor.allCases)
    func dataTask_whenTheChainIsLongerThanWhatTheExecutorCanFollow_failsOrFollowsButNeverWithTheSystemError(
        executor: TransferTestExecutor
    ) async throws {
        // Given: 25 redirects, and a `max` that allows them all.
        let hops = 25

        let server = try await ScriptedServer { received in
            let hop = received.uri.split(separator: "/").last.flatMap { Int($0) } ?? 0
            return hop < hops ? .redirect(to: "/hop/\(hop + 1)") : .ok()
        }

        // When
        let outcome: Result<Int, any Error> = await {
            do {
                let result = try await completing(within: 60) {
                    try await DataTask {
                        BaseURL(.http, host: "127.0.0.1:\(server.port)")
                        Path("/hop/0")

                        executor.pinnedSession.enableRedirectFollow(max: 100, allowCycles: false)
                    }
                    .result()
                }

                return .success(Int(result.head.status.code))
            } catch {
                return .failure(error)
            }
        }()

        await server.shutdown()

        // Then
        if executor.isNIO {
            #expect((try? outcome.get()) == 200)
        } else {
            let error = try #require(outcome.failureValue as? RedirectError)
            #expect(error.reason == .limitReached)
        }
    }
}

extension Result {

    fileprivate var failureValue: Failure? {
        if case .failure(let error) = self {
            return error
        }

        return nil
    }
}

#endif
