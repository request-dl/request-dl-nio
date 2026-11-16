//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation

/// Creating a `URLSessionTask` on an invalidated session raises an Objective-C exception
/// (`NSGenericException`), which Swift cannot catch: the process ends. `shutdown()` and a request
/// that starts on the same client therefore have to agree, atomically, on which of them came first.
@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsURLSessionClientShutdownTests {

    @Test
    func execute_whenClientWasShutDown_throwsInsteadOfCreatingATaskOnTheInvalidatedSession() async throws {
        // Given
        let client = try Internals.URLSessionClient(configuration: .ephemeral)
        let url = try #require(URL(string: "https://127.0.0.1:1/"))

        #expect(try await client.shutdown())

        // When / Then: every overload that starts a task.
        await #expect(throws: Internals.URLSessionClient.ClientClosedError.self) {
            _ = try await client.execute(request: URLRequest(url: url))
        }

        await #expect(throws: Internals.URLSessionClient.ClientClosedError.self) {
            _ = try await client.execute(request: URLRequest(url: url), readingMode: .length(1_024))
        }

        await #expect(throws: Internals.URLSessionClient.ClientClosedError.self) {
            _ = try await client.execute(
                request: URLRequest(url: url),
                readingMode: .length(1_024),
                uploadingBytes: .zero,
                decompression: .disabled,
                cache: nil,
                logger: nil
            )
        }

        #expect(!client.isRunning)
    }

    @Test
    func shutdown_whenCalledTwice_onlyInvalidatesOnce() async throws {
        // Given
        let client = try Internals.URLSessionClient(configuration: .ephemeral)

        // When
        let first = try await client.shutdown()
        let second = try await client.shutdown()

        // Then
        #expect(first)
        #expect(!second)
    }

    /// Whichever of the two wins, the other has to know: either the request registered first, and
    /// `shutdown()` finds the client busy and leaves it alone, or `shutdown()` closed it first and the
    /// request is refused. Never a request on a session that was invalidated underneath it.
    @Test
    func shutdown_whenRacingARequestStartingOnTheSameClient_neverLosesTheSessionUnderIt() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString

        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: "Hello"), at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))

        for _ in 0..<25 {
            let client = try Internals.URLSessionClient(configuration: .ephemeral)

            // When
            async let request: Bool = {
                do {
                    let result = try await client.execute(
                        request: URLRequest(url: url),
                        delegate: AcceptAnyServerTrustDelegate()
                    )

                    return result.head.status.code == 200
                } catch is Internals.URLSessionClient.ClientClosedError {
                    return false
                }
            }()

            async let shutdown = client.shutdown()

            let (served, closed) = try await (request, shutdown)

            // Then: exactly one of them got the client. A request that was served ran to the end on
            // a session nobody invalidated, so the shutdown must have found the client busy (or
            // have come after the request was over, which a request this short makes possible too).
            #expect(served || closed)
        }
    }
}

/// Test-only stand-in for the real TLS challenge handling; see the identical delegate in
/// `InternalsURLSessionClientMetricsTests`: `LocalServer` is always TLS-terminated with a throwaway
/// self-signed certificate.
private final class AcceptAnyServerTrustDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard
            challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
            let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }
}

#endif
