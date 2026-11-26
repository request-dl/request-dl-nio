//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(NIOCore)

/// `hiddenOnRedirect(_:)`, end to end through the public API: the headers a caller marked as not to
/// follow a redirect, on every executor and however the redirect is followed.
///
/// `ScriptedServer`s are the origins (two ports are two origins) and say what reached the wire.
struct RedirectHiddenHeadersTests {

    // MARK: - Inner types

    typealias Mode = RedirectExecutorParityTests.Mode

    /// What was received by the origin the request was sent to (`first`, then the hop that stayed
    /// on it, if any) and by the one a redirect led to (`last`).
    struct Outcome {
        let first: ScriptedServer.Received
        let last: ScriptedServer.Received
    }

    enum Marking: String, Sendable, CaseIterable, CustomTestStringConvertible {
        case notMarked
        case otherOrigins
        case anyRedirect

        var testDescription: String { rawValue }

        var scope: RedirectHeaderScope? {
            switch self {
            case .notMarked: nil
            case .otherOrigins: .otherOrigins
            case .anyRedirect: .anyRedirect
            }
        }
    }

    // MARK: - Tests

    /// The default scope: gone on the way to another origin, as the built-in credentials are.
    @Test(arguments: TransferTestExecutor.allCases, [Mode.standard, .follow, .strategy])
    func dataTask_whenHiddenOnRedirectAndRedirectedToAnotherOrigin_doesNotForwardTheHeader(
        executor: TransferTestExecutor,
        mode: Mode
    ) async throws {
        // When
        let outcome = try await run(executor: executor, mode: mode, crossOrigin: true) {
            CustomHeader(name: "X-Api-Key", value: "secret").hiddenOnRedirect()
        }

        // Then
        #expect(outcome.first.header("X-Api-Key") == "secret")
        #expect(outcome.last.header("X-Api-Key") == nil)
    }

    /// The same rule as the built-in credentials: a redirect that stays on the origin keeps it.
    @Test(arguments: TransferTestExecutor.allCases, [Mode.standard, .follow, .strategy])
    func dataTask_whenHiddenOnRedirectAndRedirectedWithinTheSameOrigin_forwardsTheHeader(
        executor: TransferTestExecutor,
        mode: Mode
    ) async throws {
        // When
        let outcome = try await run(executor: executor, mode: mode, crossOrigin: false) {
            CustomHeader(name: "X-Api-Key", value: "secret").hiddenOnRedirect(.otherOrigins)
        }

        // Then
        #expect(outcome.first.header("X-Api-Key") == "secret")
        #expect(outcome.last.header("X-Api-Key") == "secret")
    }

    @Test(arguments: TransferTestExecutor.allCases, [Mode.standard, .follow, .strategy])
    func dataTask_whenHiddenOnAnyRedirectAndRedirectedWithinTheSameOrigin_doesNotForwardTheHeader(
        executor: TransferTestExecutor,
        mode: Mode
    ) async throws {
        // When
        let outcome = try await run(executor: executor, mode: mode, crossOrigin: false) {
            CustomHeader(name: "X-Api-Key", value: "secret").hiddenOnRedirect(.anyRedirect)
        }

        // Then
        #expect(outcome.first.header("X-Api-Key") == "secret")
        #expect(outcome.last.header("X-Api-Key") == nil)
    }

    @Test(arguments: TransferTestExecutor.allCases, [Mode.standard, .follow, .strategy])
    func dataTask_whenHiddenOnAnyRedirectAndRedirectedToAnotherOrigin_doesNotForwardTheHeader(
        executor: TransferTestExecutor,
        mode: Mode
    ) async throws {
        // When
        let outcome = try await run(executor: executor, mode: mode, crossOrigin: true) {
            CustomHeader(name: "X-Api-Key", value: "secret").hiddenOnRedirect(.anyRedirect)
        }

        // Then
        #expect(outcome.first.header("X-Api-Key") == "secret")
        #expect(outcome.last.header("X-Api-Key") == nil)
    }

    /// A header that was not marked is forwarded, as before, and so is one that was marked with
    /// another name next to it.
    @Test(arguments: TransferTestExecutor.allCases, [Mode.standard, .follow, .strategy])
    func dataTask_whenAnotherHeaderIsHiddenOnRedirect_stillForwardsTheOnesNotMarked(
        executor: TransferTestExecutor,
        mode: Mode
    ) async throws {
        for crossOrigin in [true, false] {
            // When
            let outcome = try await run(executor: executor, mode: mode, crossOrigin: crossOrigin) {
                CustomHeader(name: "X-Api-Key", value: "secret").hiddenOnRedirect(.anyRedirect)
                CustomHeader(name: "X-Trace", value: "trace-1")
            }

            // Then
            #expect(outcome.last.header("X-Api-Key") == nil, "crossOrigin: \(crossOrigin)")
            #expect(outcome.last.header("X-Trace") == "trace-1", "crossOrigin: \(crossOrigin)")
        }
    }

    @Test(arguments: TransferTestExecutor.allCases, [Mode.standard, .follow, .strategy])
    func dataTask_whenNoHeaderIsHiddenOnRedirect_forwardsTheCustomHeaderToAnotherOrigin(
        executor: TransferTestExecutor,
        mode: Mode
    ) async throws {
        // When
        let outcome = try await run(executor: executor, mode: mode, crossOrigin: true) {
            CustomHeader(name: "X-Api-Key", value: "secret")
        }

        // Then
        #expect(outcome.last.header("X-Api-Key") == "secret")
    }

    /// Every header under the group is marked, the ones that are not custom included, and what is
    /// next to the group is not.
    @Test(arguments: TransferTestExecutor.allCases, Marking.allCases)
    func dataTask_whenAHeaderGroupIsHiddenOnRedirect_marksEveryHeaderInIt(
        executor: TransferTestExecutor,
        marking: Marking
    ) async throws {
        for mode in Mode.allCases {
            // When
            let outcome = try await run(executor: executor, mode: mode, crossOrigin: false) {
                if let scope = marking.scope {
                    HeaderGroup {
                        CustomHeader(name: "X-Api-Key", value: "secret")
                        CustomHeader(name: "X-Tenant", value: "acme")
                        RefererHeader("https://example.com/")
                    }
                    .hiddenOnRedirect(scope)
                } else {
                    HeaderGroup {
                        CustomHeader(name: "X-Api-Key", value: "secret")
                        CustomHeader(name: "X-Tenant", value: "acme")
                        RefererHeader("https://example.com/")
                    }
                }

                CustomHeader(name: "X-Outside", value: "kept")
            }

            // Then
            let hidden = marking == .anyRedirect

            #expect(outcome.first.header("X-Api-Key") == "secret")
            #expect(outcome.first.header("X-Tenant") == "acme")
            #expect(outcome.last.header("X-Api-Key") == (hidden ? nil : "secret"))
            #expect(outcome.last.header("X-Tenant") == (hidden ? nil : "acme"))
            #expect(outcome.last.header("Referer") == (hidden ? nil : "https://example.com/"))
            #expect(outcome.last.header("X-Outside") == "kept")
        }
    }

    @Test(arguments: TransferTestExecutor.allCases, [Mode.standard, .follow, .strategy])
    func dataTask_whenAHeaderGroupIsHiddenOnRedirectAndRedirectedToAnotherOrigin_doesNotForwardItsHeaders(
        executor: TransferTestExecutor,
        mode: Mode
    ) async throws {
        // When
        let outcome = try await run(executor: executor, mode: mode, crossOrigin: true) {
            HeaderGroup {
                CustomHeader(name: "X-Api-Key", value: "secret")
                CustomHeader(name: "X-Tenant", value: "acme")
            }
            .hiddenOnRedirect()

            CustomHeader(name: "X-Outside", value: "kept")
        }

        // Then
        #expect(outcome.first.header("X-Api-Key") == "secret")
        #expect(outcome.last.header("X-Api-Key") == nil)
        #expect(outcome.last.header("X-Tenant") == nil)
        #expect(outcome.last.header("X-Outside") == "kept")
    }

    /// `URLSession` takes `Authorization` off a redirect and the executor gives it back to one
    /// that stays on the origin: a caller that asked for it to be removed on any redirect is not
    /// given it back.
    @Test(arguments: TransferTestExecutor.allCases, [Mode.standard, .follow, .strategy])
    func dataTask_whenAuthorizationIsHiddenOnAnyRedirect_doesNotGetItBackWithinTheSameOrigin(
        executor: TransferTestExecutor,
        mode: Mode
    ) async throws {
        // When
        let outcome = try await run(executor: executor, mode: mode, crossOrigin: false) {
            CustomHeader(name: "Authorization", value: "Bearer secret").hiddenOnRedirect(.anyRedirect)
            CustomHeader(name: "Proxy-Authorization", value: "Basic c2VjcmV0").hiddenOnRedirect(.anyRedirect)
        }

        // Then
        #expect(outcome.first.header("Authorization") == "Bearer secret")
        #expect(outcome.last.header("Authorization") == nil)
        #expect(outcome.last.header("Proxy-Authorization") == nil)
    }

    /// The built-in credentials keep following a redirect within the origin when the caller marks
    /// them for other origins only, which they already are.
    @Test(arguments: TransferTestExecutor.allCases, [Mode.standard, .follow, .strategy])
    func dataTask_whenAuthorizationIsHiddenOnRedirect_keepsItWithinTheSameOrigin(
        executor: TransferTestExecutor,
        mode: Mode
    ) async throws {
        // When
        let outcome = try await run(executor: executor, mode: mode, crossOrigin: false) {
            Authorization(.bearer, token: "secret").hiddenOnRedirect()
        }

        // Then
        #expect(outcome.last.header("Authorization") == "Bearer secret")
    }

    /// A strategy decides after the executor has taken the header off, and what it answers with is
    /// taken off again: it cannot put back a header that must not follow the redirect.
    @Test(arguments: TransferTestExecutor.allCases, [true, false])
    func dataTask_whenAStrategyAddsAHiddenHeaderBack_doesNotForwardIt(
        executor: TransferTestExecutor,
        crossOrigin: Bool
    ) async throws {
        // Given
        let seenByStrategy = LockedValueBox<String?>("not called")

        // When
        let outcome = try await run(
            executor: executor,
            mode: .strategy,
            crossOrigin: crossOrigin,
            session: { session in
                session.onRedirect { context in
                    seenByStrategy.withLockedValue {
                        $0 = context.redirectRequest.headers.first(name: "X-Api-Key")
                    }

                    var request = context.redirectRequest
                    request.headers.add(name: "X-Api-Key", value: "added-back")
                    return .follow(request)
                }
            },
            headers: {
                CustomHeader(name: "X-Api-Key", value: "secret").hiddenOnRedirect(.anyRedirect)
            }
        )

        // Then
        #expect(seenByStrategy.withLockedValue { $0 } == nil)
        #expect(outcome.last.header("X-Api-Key") == nil)
    }

    /// A chain that goes through several hops: the header is gone from each of the ones after
    /// the first, not only from the first hop.
    @Test(arguments: TransferTestExecutor.allCases, [Mode.standard, .follow, .strategy])
    func dataTask_whenHiddenOnAnyRedirectAndRedirectedTwice_doesNotForwardTheHeaderOnAnyHop(
        executor: TransferTestExecutor,
        mode: Mode
    ) async throws {
        // Given
        let server = try await ScriptedServer { received in
            switch received.uri {
            case "/start": .redirect(to: "/mid")
            case "/mid": .redirect(to: "/end")
            default: .ok()
            }
        }

        // When
        _ = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path("/start")
            CustomHeader(name: "X-Api-Key", value: "secret").hiddenOnRedirect(.anyRedirect)

            mode.apply(to: executor.pinnedSession)
        }
        .result()

        let requests = server.requests
        await server.shutdown()

        // Then
        #expect(requests.map(\.uri) == ["/start", "/mid", "/end"])
        #expect(requests.map { $0.header("X-Api-Key") } == ["secret", nil, nil])
    }

    // MARK: - Private methods

    /// Sends `/start` to an origin that redirects it, to the same origin (`/next`) or to another
    /// (`/final`), and returns what the origin and the destination received.
    private func run(
        executor: TransferTestExecutor,
        mode: Mode,
        crossOrigin: Bool,
        session: ((Session) -> Session)? = nil,
        @PropertyBuilder headers: () -> some Property
    ) async throws -> Outcome {
        let headers = headers()

        let destination = try await ScriptedServer { _ in .ok() }
        let target = "\(destination.origin)/final"

        let origin = try await ScriptedServer { received in
            guard received.uri == "/start" else {
                return .ok()
            }

            return .redirect(to: crossOrigin ? target : "/next")
        }

        let result = try await DataTask {
            BaseURL(.http, host: "127.0.0.1:\(origin.port)")
            Path("/start")

            headers

            if let session {
                session(executor.pinnedSession)
            } else {
                mode.apply(to: executor.pinnedSession)
            }
        }
        .result()

        let first = try #require(origin.requests.first)
        let last = try #require(crossOrigin ? destination.requests.first : origin.requests.last)

        await origin.shutdown()
        await destination.shutdown()

        #expect(result.head.status.code == 200)

        return Outcome(first: first, last: last)
    }
}

#endif
