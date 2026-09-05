//
// See LICENSE for this package's licensing information.
//

import NIOConcurrencyHelpers
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

/// End-to-end coverage for ``RedirectStrategy`` through the actual public API (`Session
/// .redirectStrategy(_:)`/`.onRedirect(_:)`) over a real `LocalServer` redirect, on both
/// transports.
///
/// `InternalsNIORedirectStrategyAdapterTests` and `InternalsURLSessionClientRedirectStrategyTests`
/// (`RequestDLInternalsTests`) already cover the two transports' own redirect mechanics in
/// isolation, each driving `Internals.RedirectStrategy` directly. What neither exercises is the
/// bridge in between -- `InternalsRedirectStrategyAdapter`/`ClosureRedirectStrategy`, and the
/// public `RedirectContext`/`RedirectRequest`/`RedirectHistoryEntry` themselves -- since a caller
/// only ever reaches those through `Session`, not through `Internals` directly.
struct RedirectStrategyDataTaskTests {

    @Test
    func dataTask_whenOnRedirectOverURLSession_isInvokedAndControlsTheRedirect() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let origin = "/" + UUID().uuidString
        let destination = "/" + UUID().uuidString
        let certificate = Certificates().server()
        let output = "Redirected over URLSession!"

        localServer.cleanup(at: origin)
        localServer.cleanup(at: destination)

        localServer.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": destination], data: Data()),
            at: origin
        )
        localServer.insert(
            try LocalServer.ResponseConfiguration(jsonObject: output),
            at: destination
        )

        defer {
            localServer.cleanup(at: origin)
            localServer.cleanup(at: destination)
        }

        let capturedContext = NIOLockedValueBox<RedirectContext?>(nil)

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(origin)

            Session.localServer
                .preferredExecutor(.urlSession)
                .onRedirect { context in
                    capturedContext.withLockedValue { $0 = context }
                    return .follow(context.redirectRequest)
                }

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == output)

        let context = try #require(capturedContext.withLockedValue { $0 })
        #expect(context.redirectRequest.url.hasSuffix(destination))
        #expect(context.history.count == 1)
        #expect(context.redirectCount == 0)
    }

    /// `.redirectStrategy`/`.onRedirect` over the `.nio`/`.nioTransportServices` executors drive
    /// AsyncHTTPClient's delegate-based `execute(request:delegate:...)` API, as opposed to its
    /// Concurrency `execute(_:deadline:logger:)` family that the `.urlSession` executor has no
    /// need for. AsyncHTTPClient's own `.strategy` redirect mode is wired up for both --
    /// `RedirectHandler`/`RedirectStrategyDelegateBridge.swift` on its side bridge a strategy's
    /// decision back into the delegate API's request/body types -- so this follows the redirect
    /// exactly like the `.urlSession` executor does above.
    @Test
    func dataTask_whenRedirectStrategyOverNIO_isInvokedAndControlsTheRedirect() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let origin = "/" + UUID().uuidString
        let destination = "/" + UUID().uuidString
        let certificate = Certificates().server()
        let output = "Redirected over NIO!"

        localServer.cleanup(at: origin)
        localServer.cleanup(at: destination)

        localServer.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": destination], data: Data()),
            at: origin
        )
        localServer.insert(
            try LocalServer.ResponseConfiguration(jsonObject: output),
            at: destination
        )

        defer {
            localServer.cleanup(at: origin)
            localServer.cleanup(at: destination)
        }

        let capturedContext = NIOLockedValueBox<RedirectContext?>(nil)

        struct RecordingStrategy: RedirectStrategy {
            let capturedContext: NIOLockedValueBox<RedirectContext?>

            func redirectDecision(for context: RedirectContext) throws -> RedirectDecision {
                capturedContext.withLockedValue { $0 = context }
                return .follow(context.redirectRequest)
            }
        }

        // When
        let data = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(origin)

            Session.localServer
                .preferredExecutor(.nio)
                .redirectStrategy(RecordingStrategy(capturedContext: capturedContext))

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .extractPayload()
        .result()

        let result = try HTTPResult<String>(data)

        // Then
        #expect(result.response == output)

        let context = try #require(capturedContext.withLockedValue { $0 })
        #expect(context.redirectRequest.url.hasSuffix(destination))
        #expect(context.history.count == 1)
        #expect(context.redirectCount == 0)
    }

    @Test
    func dataTask_whenRedirectStrategyDoesNotFollowOverURLSession_returnsRedirectResponseUnfollowed() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let origin = "/" + UUID().uuidString
        let destination = "/" + UUID().uuidString
        let certificate = Certificates().server()

        localServer.cleanup(at: origin)
        localServer.cleanup(at: destination)

        localServer.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": destination], data: Data()),
            at: origin
        )

        defer {
            localServer.cleanup(at: origin)
            localServer.cleanup(at: destination)
        }

        // When
        let result = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(origin)

            Session.localServer
                .preferredExecutor(.urlSession)
                .onRedirect { _ in .doNotFollow }

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .result()

        // Then
        #expect(result.head.status.code == 302)
    }

    /// AsyncHTTPClient's delegate-based path used to fail the whole task for `.doNotFollow`
    /// (resuming normal delivery of the response that triggered the redirect had no route back
    /// from the state its response-delivery state machine had already committed to). Fixed by
    /// asking the strategy the moment the response head arrives, before any body byte is read --
    /// see `RedirectHandler.earlyStrategyDecision(head:)` on the async-http-client fork.
    @Test
    func dataTask_whenRedirectStrategyDoesNotFollowOverNIO_returnsRedirectResponseUnfollowed() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let origin = "/" + UUID().uuidString
        let destination = "/" + UUID().uuidString
        let certificate = Certificates().server()

        localServer.cleanup(at: origin)
        localServer.cleanup(at: destination)

        localServer.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": destination], data: Data()),
            at: origin
        )

        defer {
            localServer.cleanup(at: origin)
            localServer.cleanup(at: destination)
        }

        // When
        let result = try await DataTask {
            BaseURL(localServer.baseURL)
            Path(origin)

            Session.localServer
                .preferredExecutor(.nio)
                .onRedirect { _ in .doNotFollow }

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }
        .result()

        // Then
        #expect(result.head.status.code == 302)
    }
}
