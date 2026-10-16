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

/// A redirect that can't be followed fails with the same ``RedirectError`` whichever executor ran
/// the request: `URLSession` and AsyncHTTPClient each have an error of their own for these
/// conditions, and neither is what a caller should have to catch.
struct RedirectErrorTests {

    private enum Executor: Sendable, CaseIterable, CustomTestStringConvertible {
        #if canImport(NIOCore)
        case nio
        #endif

        #if canImport(Darwin)
        case urlSession
        #endif

        var testDescription: String {
            switch self {
            #if canImport(NIOCore)
            case .nio:
                return "nio"
            #endif
            #if canImport(Darwin)
            case .urlSession:
                return "urlSession"
            #endif
            }
        }

        /// The local server's session, pinned to this executor.
        var session: Session {
            switch self {
            #if canImport(NIOCore)
            case .nio:
                return Session.localServer.requiredExecutor(.nio)
            #endif
            #if canImport(Darwin)
            case .urlSession:
                return Session.localServer.requiredExecutor(.urlSession)
            #endif
            }
        }
    }

    /// A server that answers each of `paths` with a redirect to the next one, the last with a body.
    private static func serve(
        _ localServer: LocalServer,
        redirecting paths: [String],
        to destination: String?
    ) throws {
        for (index, path) in paths.enumerated() {
            let next = index + 1 < paths.count ? paths[index + 1] : destination

            localServer.cleanup(at: path)

            if let next {
                localServer.insert(
                    LocalServer.ResponseConfiguration(status: .found, headers: ["Location": next], data: Data()),
                    at: path
                )
            } else {
                localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "unreachable"), at: path)
            }
        }
    }

    // MARK: - Tests

    /// A chain longer than the limit.
    @Test(arguments: Executor.allCases)
    private func aChainLongerThanTheLimit_failsWithLimitReached(_ executor: Executor) async throws {
        // Given: origin -> hop -> destination, against a limit of one redirect.
        let localServer = try await LocalServer(.standard)
        let certificate = Certificates().server()
        let paths = (0..<3).map { _ in "/" + UUID().uuidString }

        try Self.serve(localServer, redirecting: paths, to: nil)
        defer {
            for path in paths {
                localServer.cleanup(at: path)
            }
        }

        // Then
        let error = try await #require(throws: RedirectError.self) {
            try await completing(within: 60) {
                _ = try await DataTask {
                    BaseURL(localServer.baseURL)
                    Path(paths[0])

                    executor.session.enableRedirectFollow(max: 1, allowCycles: false)

                    SecureConnection {
                        TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
                    }
                }
                .result()
            }
        }

        #expect(error.reason == .limitReached)
    }

    /// A redirect back to a URL already visited.
    @Test(arguments: Executor.allCases)
    private func aRedirectBackToAVisitedURL_failsWithCycleDetected(_ executor: Executor) async throws {
        // Given: origin -> hop -> origin.
        let localServer = try await LocalServer(.standard)
        let certificate = Certificates().server()
        let paths = (0..<2).map { _ in "/" + UUID().uuidString }

        try Self.serve(localServer, redirecting: paths, to: paths[0])
        defer {
            for path in paths {
                localServer.cleanup(at: path)
            }
        }

        // Then
        let error = try await #require(throws: RedirectError.self) {
            try await completing(within: 60) {
                _ = try await DataTask {
                    BaseURL(localServer.baseURL)
                    Path(paths[0])

                    executor.session.enableRedirectFollow(max: 5, allowCycles: false)

                    SecureConnection {
                        TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
                    }
                }
                .result()
            }
        }

        #expect(error.reason == .cycleDetected)
    }

    /// A strategy that answers with a URL that can't be parsed.
    @Test(arguments: Executor.allCases)
    private func aStrategyThatAnswersWithAnInvalidURL_failsWithInvalidURL(_ executor: Executor) async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let certificate = Certificates().server()
        let paths = (0..<2).map { _ in "/" + UUID().uuidString }

        try Self.serve(localServer, redirecting: paths, to: nil)
        defer {
            for path in paths {
                localServer.cleanup(at: path)
            }
        }

        struct InvalidURLStrategy: RedirectStrategy {
            func redirectDecision(for context: RedirectContext) throws -> RedirectDecision {
                var request = context.redirectRequest
                request.url = "http://[not a url"
                return .follow(request)
            }
        }

        // Then
        let error = try await #require(throws: RedirectError.self) {
            try await completing(within: 60) {
                _ = try await DataTask {
                    BaseURL(localServer.baseURL)
                    Path(paths[0])

                    executor.session.redirectStrategy(InvalidURLStrategy())

                    SecureConnection {
                        TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
                    }
                }
                .result()
            }
        }

        #expect(error.reason == .invalidURL)
        #expect(!String(describing: error).contains("not a url"))
    }

    /// A redirect that isn't followed is not an error: the response that asked for it is the result.
    @Test(arguments: Executor.allCases)
    private func aRedirectThatIsNotFollowed_isNotAnError(_ executor: Executor) async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let certificate = Certificates().server()
        let paths = (0..<2).map { _ in "/" + UUID().uuidString }

        try Self.serve(localServer, redirecting: paths, to: nil)
        defer {
            for path in paths {
                localServer.cleanup(at: path)
            }
        }

        // When
        let result = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(paths[0])

            executor.session.disableRedirect()

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .result()

        // Then
        #expect(result.head.status.code == 302)
    }

    // MARK: - Before there is a response

    /// A redirect can fail in a step ahead of the transport too (a revalidation that is redirected
    /// in a circle, say): the same public error.
    @Test
    private func aRedirectThatFailsBeforeThereIsAResponse_failsWithTheSameError() async throws {
        // Given
        let task = RawTask(content: EmptyProperty())

        // Then
        let error = try await #require(throws: RedirectError.self) {
            try await task.surfacingResourceTimeout {
                throw Internals.RedirectError(.cycleDetected)
            }
        }

        #expect(error.reason == .cycleDetected)
    }

    // MARK: - Description

    @Test(arguments: [RedirectError.Reason.limitReached, .cycleDetected, .invalidURL])
    private func everyReason_describesItself(_ reason: RedirectError.Reason) {
        #expect(!String(describing: RedirectError(reason)).isEmpty)
    }
}
