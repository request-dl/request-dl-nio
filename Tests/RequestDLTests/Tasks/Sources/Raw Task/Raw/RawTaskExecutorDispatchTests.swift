//
// See LICENSE for this package's licensing information.
//

import NIOCore
import NIOPosix
import Testing

@testable import RequestDL
@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.UUID
#endif

/// `RawTask.result()` dispatches through `Internals.Session.resolvedClient()` (backed by
/// `Internals.ClientManager.shared`, the same pool every real request in the process shares)
/// instead of the NIO-only `client()`, so `preferredExecutor`/`requiredExecutor` decide which
/// backend a real `DataTask` runs over.
///
/// `InternalsClientManagerExecutorTests` (`RequestDLInternalsTests`) already proved
/// `Internals.ClientManager.resolvedClient(provider:sessionConfiguration:)` resolves and caches a
/// working `.urlSession` client, using a hand-built `Internals.ClientManager`/`SessionProvider` --
/// deliberately isolated from the `Property`/`Resolve` pipeline and from `Internals.ClientManager
/// .shared`. This file proves the layer above that: a real `DataTask`, resolved through an actual
/// `Property` tree exactly as an app would build one, and dispatched via the *same* shared pool
/// `RawTask.result()` itself reads from -- not a fresh, test-isolated manager.
struct RawTaskExecutorDispatchTests {

    @Test
    func dataTask_whenNoExecutorPreferenceSet_actuallyDispatchesOverURLSessionOnDarwin() async throws {
        // Given -- a config compatible with every executor, so `.urlSession` is
        // `resolveExecutor()`'s own default preference, not something forced here. A
        // session id unique to this test run keeps it off `Session.localServer`'s shared pooled
        // entry, so nothing else running concurrently can affect (or be affected by) the
        // `Internals.ClientManager.shared` lookup below.
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let content = TestProperty {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session("com.requestdl.tests.7b3-dispatch.\(UUID())")

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }

        // When -- through the real public API, exactly as an app would call it. No executor
        // modifier anywhere in `content` above.
        let data = try await DataTask { content }.extractPayload().result()

        let result = try HTTPResult<String>(data)
        #expect(result.response == output)

        // Then -- resolving the identical property tree again and asking
        // `Internals.ClientManager.shared` (the pool the `DataTask` call above actually used)
        // what it holds for this exact provider is what proves the *real* call dispatched over
        // `.urlSession`, rather than merely that `.urlSession` was resolvable in isolation.
        let resolved = try await resolve(content)

        guard case .urlSession = try await resolved.session.resolvedClient() else {
            Issue.record("Expected the DataTask call above to have dispatched over .urlSession")
            return
        }
    }

    @Test
    func dataTask_whenNIORequired_actuallyDispatchesOverNIOEvenThoughURLSessionWouldBeCompatible() async throws {
        // Given -- same shape as above (would default to `.urlSession` on Darwin), but this time
        // pinned to `.nio` explicitly. Regression coverage for the bug this phase's own testing
        // caught: `requiredExecutor(.nio)` used to validate without ever actually being the
        // executor a real request dispatched over -- `resolveExecutor()` read only
        // `preferredExecutor`, so a `.urlSession`-compatible config kept resolving there anyway.
        // See `InternalsSessionConfigurationExecutorTests`'s "resolveExecutor() with
        // requiredExecutor" section for the unit-level fix; this is the same fact proven one
        // layer up, through a real `DataTask` round trip.
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let certificate = Certificates().server()
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let content = TestProperty {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session("com.requestdl.tests.7b3-dispatch.\(UUID())")
                .requiredExecutor(.nio)

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }
        }

        // When
        let data = try await DataTask { content }.extractPayload().result()

        let result = try HTTPResult<String>(data)
        #expect(result.response == output)

        // Then
        let resolved = try await resolve(content)

        guard case .nio = try await resolved.session.resolvedClient() else {
            Issue.record("Expected the DataTask call above to have dispatched over .nio")
            return
        }
    }

    /// Cancellation, validated for real. `Internals.TaskSeed` (transport-agnostic) cancels when
    /// the response is *dropped*, not when the
    /// awaiting `_Concurrency.Task` is marked cancelled -- nothing in the iteration path
    /// (`AsyncBytes.AsyncIterator.next()`, `Internals.AsyncStream`) checks
    /// `Task.isCancelled`/`Task.checkCancellation()`. So the whole round trip below runs inside
    /// one scope: read the one chunk `withPartialResponseServer` ever sends, then let that scope
    /// end -- dropping both the loop's iterator and the `TaskResult<AsyncBytes>` itself, the only
    /// two things holding the seed alive.
    ///
    /// `LocalServer` always answers fully and immediately, and a "just make the body big" version
    /// of this test (tried first) turned out not to prove anything: over a local loopback
    /// connection, even a multi-megabyte body transfers, and the underlying `URLSessionTask`
    /// completes naturally, well before any scope-based cancellation logic gets a chance to do
    /// anything -- the test passed whether or not cancellation actually worked. `withPartialResponseServer`
    /// sends valid HTTP/1.1 headers plus a small body, then goes silent while declaring a
    /// `Content-Length` it never finishes -- keeping the connection genuinely, indefinitely
    /// "mid-transfer" until this test explicitly ends it, so the poll below can only pass because
    /// dropping the response actually cancelled something still running.
    @Test
    func downloadTask_whenResponseDroppedMidFlight_actuallyCancelsTheUnderlyingURLSessionClient() async throws {
        try await withPartialResponseServer { port in
            // Given -- plain HTTP: this server speaks raw bytes, not TLS, and `.urlSession`
            // reaches `127.0.0.1` over HTTP with no ATS issue in this test harness (confirmed by
            // running it, not assumed).
            let content = TestProperty {
                BaseURL(.http, host: "127.0.0.1:\(port)")

                Session("com.requestdl.tests.7b4-cancel.\(UUID())")
                    .requiredExecutor(.urlSession)

                // The default reading mode (`.length(1_024)`) waits for a full 1024-byte chunk
                // before yielding anything -- `withPartialResponseServer` only ever sends 19
                // bytes ("partial-body-bytes") before going silent, so the default would wait
                // forever for a chunk boundary that can never arrive. A length well under that
                // lets the first (and only) chunk surface promptly instead.
                ReadingMode(length: 4)
            }

            let resolved = try await resolve(content)

            guard case .urlSession(let client) = try await resolved.session.resolvedClient() else {
                Issue.record("Expected .urlSession")
                return
            }

            #expect(!client.isRunning)

            // When
            var observedRunningMidFlight = false

            try await {
                let result = try await DownloadTask { content }.result()
                for try await _ in result.payload {
                    // The server has already gone silent for good at this point, having declared
                    // far more `Content-Length` than it will ever actually send -- genuinely
                    // mid-flight, not a download that happened to finish before this loop got
                    // here.
                    observedRunningMidFlight = client.isRunning
                    break
                }
            }()

            #expect(observedRunningMidFlight)

            // Then -- `didCompleteWithError:` releases the operation-queue slot asynchronously,
            // so poll briefly rather than asserting immediately after the scope above ends.
            var stillRunning = client.isRunning
            for _ in 0..<50 where stillRunning {
                try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
                stillRunning = client.isRunning
            }

            #expect(!stillRunning)
        }
    }

    /// Companion to `DataTaskTests.dataTask_whenResourceTimeoutAlreadyElapsed_throwsResourceTimeoutError`:
    /// that one proves `Timeout(.resource)` throws `ResourceTimeoutError` at all, but with a
    /// deadline so short it has already elapsed before the request even reaches the network --
    /// it says nothing about whether the deadline actually tears down a connection that's
    /// genuinely still running, nor which executor it ran that proof against (`Session.localServer`
    /// carries no executor preference, so it only happens to resolve to `.urlSession` by Darwin's
    /// own default -- see `dataTask_whenNoExecutorPreferenceSet_actuallyDispatchesOverURLSessionOnDarwin`
    /// above).
    ///
    /// This pins `.urlSession` explicitly, so this regression coverage can't silently go stale
    /// if that default ever changes, and reuses `withPartialResponseServer` -- headers plus a
    /// small body, then silence forever -- so the deadline has to fire against a connection
    /// that's demonstrably still open, the same technique
    /// `downloadTask_whenResponseDroppedMidFlight_actuallyCancelsTheUnderlyingURLSessionClient`
    /// above uses to prove cancellation for real instead of merely asserting an error type.
    @Test
    func dataTask_whenResourceTimeoutFiresMidFlightUnderRequiredURLSession_cancelsTheUnderlyingURLSessionTaskAndThrows()
        async throws
    {
        try await withPartialResponseServer { port in
            // Given
            let content = TestProperty {
                BaseURL(.http, host: "127.0.0.1:\(port)")

                Session("com.requestdl.tests.7b5-resource-timeout.\(UUID())")
                    .requiredExecutor(.urlSession)
                Timeout(.milliseconds(200), for: .resource)
            }

            let resolved = try await resolve(content)

            guard case .urlSession(let client) = try await resolved.session.resolvedClient() else {
                Issue.record("Expected .urlSession")
                return
            }

            #expect(!client.isRunning)

            // When / Then -- the server never finishes the body, so this can only complete by the
            // deadline actually firing.
            await #expect(throws: ResourceTimeoutError.self) {
                _ = try await DataTask { content }.extractPayload().result()
            }

            // Then -- not just an error thrown at the caller: the live `URLSessionTask` behind it
            // actually got torn down. `didCompleteWithError:` releases state asynchronously, so
            // poll briefly rather than asserting immediately.
            var stillRunning = client.isRunning
            for _ in 0..<50 where stillRunning {
                try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
                stillRunning = client.isRunning
            }

            #expect(!stillRunning)
        }
    }

    /// Confirms the identity-building failure a real mTLS `DataTask` hits under `.urlSession` on
    /// this SwiftPM test harness (no Keychain Sharing entitlement -- see
    /// `RequestConfigurationURLSessionClientMTLSTests`'s own doc comment) surfaces through the
    /// *public* API as a documented ``ClientIdentityError``, not a raw
    /// `Internals.RawBytesIdentityBuilder.Error`/`Internals.URLSessionIdentityPolicy
    /// .ConfigurationError` -- both package-visible types a real consumer app cannot even name,
    /// and whose `localizedDescription` (Foundation's generic NSError fallback, absent this fix)
    /// carries none of their own actionable `description` text. `ClientIdentityErrorTests` covers
    /// the rewrap/description logic itself in isolation; this is the same fact proven end to end,
    /// through the real `DataTask` entry point, the same way `dataTask_whenCAEnabled`
    /// (`DataTaskTests`, pinned to `.nio` specifically to avoid this exact gap) already does for
    /// the NIO backend.
    ///
    /// Deliberately does not assert on the *specific* ``ClientIdentityError/Reason`` -- this
    /// harness has been observed to hit this gap two different ways (`errSecMissingEntitlement`
    /// on `SecItemAdd`, or `errSecItemNotFound` on the identity lookup right after a successful
    /// add), and both are genuine, independently-reachable failure modes this test should pass
    /// under either way.
    @Test
    func dataTask_whenCAEnabledUnderURLSessionWithoutKeychainSharing_throwsClientIdentityError() async throws {
        let server = Certificates().server()
        let client = Certificates().client()

        let uri = "/" + UUID().uuidString

        let localServer = try await LocalServer(
            LocalServer.Configuration(
                host: "localhost",
                port: 8885,
                option: .client(client)
            )
        )

        let output = "Hello World"
        let response = try LocalServer.ResponseConfiguration(jsonObject: output)
        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let content = TestProperty {
            BaseURL(localServer.baseURL)
            Path(uri)

            Session("com.requestdl.tests.phase8-identity.\(UUID())")
                .requiredExecutor(.urlSession)

            SecureConnection {
                TrustRoots(server.certificateURL.absolutePath(percentEncoded: false))
                RequestDL.Certificates(client.certificateURL.absolutePath(percentEncoded: false))
                PrivateKey(client.privateKeyURL.absolutePath(percentEncoded: false))
            }
            .verification(.fullVerification)
        }

        do {
            _ = try await DataTask { content }.extractPayload().result()
            Issue.record("Expected this SwiftPM test harness's missing Keychain Sharing entitlement to throw")
        } catch let error as ClientIdentityError {
            // Then -- the public, documented type, not a leaked internal one, with the same
            // actionable text through both access paths a real caller might use.
            #expect(!error.description.isEmpty)
            #expect((error as any Error).localizedDescription == error.description)
        } catch {
            Issue.record("Expected ClientIdentityError, got \(type(of: error)): \(error)")
        }
    }

    /// Companion to the test above: confirms cancellation frees the throttle slot for real, not
    /// just that `isRunning` (a separate counter, released in the same completion callback but
    /// not the same value) happens to drop -- the same bar `InternalsClientConcurrencyLimitTests`
    /// already holds the NIO path to, one layer up through the public API. `Internals.ThrottledExecutor`
    /// exposes no inspectable count of its own, so this proves it indirectly: with
    /// `maximumConcurrentConnections(1)`, a second request genuinely cannot proceed while the
    /// first still holds the only permit, and does proceed once the first is cancelled.
    @Test
    func downloadTask_whenCancelledWhileHoldingTheOnlyPermit_releasesItForAQueuedRequest() async throws {
        try await withPartialResponseServer { firstPort in
            try await withCompleteResponseServer { secondPort in
                // Given -- both requests share one `Session` id/configuration (hence one pooled
                // `Internals.URLSessionClient`, hence one throttle) even though they hit two
                // different plain-HTTP servers.
                let sessionID = "com.requestdl.tests.7b4-throttle.\(UUID())"

                func content(port: Int) -> some Property {
                    TestProperty {
                        BaseURL(.http, host: "127.0.0.1:\(port)")

                        Session(sessionID)
                            .requiredExecutor(.urlSession)
                            .maximumConcurrentConnections(1)

                        // See the identical note on the test above: the default reading mode
                        // would wait forever for a 1024-byte chunk `withPartialResponseServer`
                        // never completes.
                        ReadingMode(length: 4)
                    }
                }

                let releaseSignal = ReleaseSignal()
                let secondRequestState = SecondRequestState()

                // When -- holds the only permit until explicitly told to let go, so this test
                // controls the moment of cancellation directly instead of racing a timeout
                // against it.
                async let firstDownload: Void = {
                    let result = try await DownloadTask { content(port: firstPort) }.result()
                    for try await _ in result.payload {
                        await releaseSignal.wait()
                        break
                    }
                }()

                // Gives the first request time to actually acquire the (only) permit before the
                // second is attempted at all.
                try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)

                async let secondDownload: Void = {
                    _ = try await DownloadTask { content(port: secondPort) }.result()
                    await secondRequestState.markCompleted()
                }()

                // Then -- still queued behind the first request's held permit.
                try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
                #expect(await !secondRequestState.isCompleted)

                // Cancel the first (drop its response), releasing the permit.
                await releaseSignal.fire()
                try await firstDownload

                // The second request can now actually proceed and complete.
                try await secondDownload
                #expect(await secondRequestState.isCompleted)
            }
        }
    }
}

/// Lets a test hold a cancellation at an exact, chosen moment instead of racing a fixed delay
/// against it -- used by `downloadTask_whenCancelledWhileHoldingTheOnlyPermit_releasesItForAQueuedRequest`
/// to keep the first request's throttle permit held until the test is ready to observe the second
/// request still being blocked by it.
private actor ReleaseSignal {

    private var isFired = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isFired else { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func fire() {
        isFired = true
        continuation?.resume()
        continuation = nil
    }
}

private actor SecondRequestState {

    private(set) var isCompleted = false

    func markCompleted() {
        isCompleted = true
    }
}

// MARK: - Raw servers for deterministic mid-flight state

/// A server that answers with valid HTTP/1.1 headers -- including a `Content-Length` far larger
/// than what it will ever actually send -- plus a small amount of body, then goes silent. The
/// connection stays open, genuinely "mid-transfer," for as long as the test wants, until the
/// client cancels it or the test closes the server. `LocalServer` always answers a request fully
/// and immediately, so it cannot produce this state on its own.
private func withPartialResponseServer<Result>(
    _ body: (Int) async throws -> Result
) async throws -> Result {
    try await withRawServer(PartialResponseHandler.init, body)
}

/// A server that answers a request fully and immediately, over plain HTTP -- the throttle test's
/// second, "should actually complete once let through" request.
private func withCompleteResponseServer<Result>(
    _ body: (Int) async throws -> Result
) async throws -> Result {
    try await withRawServer(CompleteResponseHandler.init, body)
}

private func withRawServer<Handler: ChannelInboundHandler & Sendable, Result>(
    _ makeHandler: @escaping @Sendable () -> Handler,
    _ body: (Int) async throws -> Result
) async throws -> Result {
    let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)

    let bootstrap = ServerBootstrap(group: group)
        .childChannelInitializer { channel in
            channel.pipeline.addHandler(makeHandler())
        }

    let serverChannel = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
    let port = serverChannel.localAddress!.port!

    do {
        let result = try await body(port)
        try? await serverChannel.close()
        try await group.shutdownGracefully()
        return result
    } catch {
        try? await serverChannel.close()
        try await group.shutdownGracefully()
        throw error
    }
}

private final class PartialResponseHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = context.channel.allocator.buffer(capacity: 256)
        buffer.writeString(
            "HTTP/1.1 200 OK\r\n"
                + "Content-Type: application/octet-stream\r\n"
                + "Content-Length: 100000000\r\n"
                + "\r\n"
                + "partial-body-bytes"
        )
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
        // Deliberately writes nothing further -- see this file's own doc comment on
        // `withPartialResponseServer` for why.
    }
}

private final class CompleteResponseHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let body = "Hello World"
        var buffer = context.channel.allocator.buffer(capacity: 256)
        buffer.writeString(
            "HTTP/1.1 200 OK\r\n"
                + "Content-Type: text/plain\r\n"
                + "Content-Length: \(body.utf8.count)\r\n"
                + "\r\n"
                + body
        )
        context.writeAndFlush(wrapOutboundOut(buffer), promise: nil)
    }
}

#endif
