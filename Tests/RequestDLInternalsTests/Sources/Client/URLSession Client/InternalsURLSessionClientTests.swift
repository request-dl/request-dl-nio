//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import Network
import Security
import SwiftAsyncStream

/// Internals-level counterpart to `RequestConfigurationURLSessionClientTests` (`RequestDLTests`):
/// exercises `Internals.URLSessionClient` directly, with a hand-built `URLRequest` rather than
/// one produced through `RequestConfiguration.buildURLRequest()` (a `RequestDL`-module type this
/// target does not depend on).
struct InternalsURLSessionClientTests {

    @Test
    func execute_whenRequestSucceeds_returnsHeadAndBody() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello World"

        let response = try LocalServer.ResponseConfiguration(
            headers: ["Content-Type": "application/json; charset=utf-8"],
            jsonObject: output
        )

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(configuration: .ephemeral)

        // When
        let result = try await client.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then
        #expect(result.head.status.code == 200)
        #expect(result.head.headerValues(named: "Content-Type").first == "application/json; charset=utf-8")

        let decoded = try JSONDecoder().decode(HTTPResult<String>.self, from: result.body)
        #expect(decoded.response == output)
    }

    @Test
    func execute_whenMaximumConcurrentConnectionsSet_stillCompletesEveryRequest() async throws {
        // Given: not a concurrency-gating assertion (that lives in
        // `InternalsThrottledExecutorTests`); just confirms the client wires the cap through
        // without breaking the request itself.
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello Throttled World"

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            maximumConcurrentConnections: 1
        )

        // When
        let result = try await client.execute(
            request: URLRequest(url: url),
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then
        let decoded = try JSONDecoder().decode(HTTPResult<String>.self, from: result.body)
        #expect(decoded.response == output)
    }

    /// `execute(request:delegate:)` bridges `dataTask(with:)` to `async`/`await` by hand
    /// (`session.data(for:delegate:)` has a confirmed crash under load; see the method's own
    /// doc comment). Unlike that Foundation API, nothing cancels the underlying
    /// `URLSessionTask` for free just because the awaiting Swift `Task` was cancelled.
    ///
    /// This confirms `CancellableTaskBox` actually restores that: cancelling the caller's `Task`
    /// both makes the call throw and stops the real network request, not just the first of the two.
    @Test
    func execute_whenTaskCancelledMidFlight_cancelsUnderlyingURLSessionTaskAndThrows() async throws {
        try await withHangingURLSessionTestServer { port in
            let client = try Internals.URLSessionClient(configuration: .ephemeral)
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/"))

            let responseTask = _Concurrency.Task {
                try await client.execute(request: URLRequest(url: url))
            }

            // Gives the request a moment to actually reach the (unresponsive) server before
            // cancelling, so this exercises a genuine in-flight cancellation rather than one
            // that races the connection attempt itself.
            try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
            #expect(client.isRunning)

            responseTask.cancel()

            await #expect(throws: (any Error).self) {
                _ = try await responseTask.value
            }

            // `didCompleteWithError:` releases the operation-queue slot asynchronously, so poll
            // briefly rather than asserting immediately after `cancel()` returns.
            var stillRunning = client.isRunning
            for _ in 0..<50 where stillRunning {
                try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
                stillRunning = client.isRunning
            }
            #expect(!stillRunning)
        }
    }

    /// Same regression as `execute_whenTaskCancelledMidFlight_cancelsUnderlyingURLSessionTaskAndThrows`
    /// above, for `execute(request:streaming:delegate:onUploadProgress:)`. This overload's
    /// continuation wasn't wrapped in `withTaskCancellationHandler` at all, unlike its sibling:
    /// cancelling the caller's `Task` while it awaited the upload response left the underlying
    /// `URLSessionTask` running unnoticed, with the throttle slot never released.
    @Test
    func execute_whenStreamingUploadTaskCancelledMidFlight_cancelsUnderlyingURLSessionTaskAndThrows() async throws {
        try await withHangingURLSessionTestServer { port in
            let client = try Internals.URLSessionClient(configuration: .ephemeral)
            var request = URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(port)/")))
            request.httpMethod = "POST"

            let (stream, continuation) = AsyncStream<Internals.Bytes>.makeStream()
            continuation.yield(Internals.Bytes(Data("payload".utf8)))
            continuation.finish()

            let responseTask = _Concurrency.Task {
                try await client.execute(request: request, streaming: stream)
            }

            // Gives the request a moment to actually reach the (unresponsive) server before
            // cancelling, so this exercises a genuine in-flight cancellation rather than one
            // that races the connection attempt itself.
            try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
            #expect(client.isRunning)

            responseTask.cancel()

            await #expect(throws: (any Error).self) {
                _ = try await responseTask.value
            }

            // `didCompleteWithError:` releases the operation-queue slot asynchronously, so poll
            // briefly rather than asserting immediately after `cancel()` returns.
            var stillRunning = client.isRunning
            for _ in 0..<50 where stillRunning {
                try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
                stillRunning = client.isRunning
            }
            #expect(!stillRunning)
        }
    }

    /// Same regression as the two tests above, for `execute(request:readingMode:delegate:)` (the
    /// standalone streamed-download overload). Also missing `withTaskCancellationHandler`
    /// entirely: cancelling the caller's `Task` while it awaited the response head left both the
    /// `URLSessionTask` and the throttle slot acquired at the top of the method (only ever
    /// released from `onDownloadComplete`, which a leaked task never reaches) stuck.
    @Test
    func execute_whenStreamedDownloadTaskCancelledMidFlight_cancelsUnderlyingURLSessionTaskAndThrows() async throws {
        try await withHangingURLSessionTestServer { port in
            let client = try Internals.URLSessionClient(configuration: .ephemeral)
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/"))

            let responseTask = _Concurrency.Task {
                try await client.execute(request: URLRequest(url: url), readingMode: .length(1_024))
            }

            // Gives the request a moment to actually reach the (unresponsive) server before
            // cancelling, so this exercises a genuine in-flight cancellation rather than one
            // that races the connection attempt itself.
            try await _Concurrency.Task.sleep(nanoseconds: 200_000_000)
            #expect(client.isRunning)

            responseTask.cancel()

            await #expect(throws: (any Error).self) {
                _ = try await responseTask.value
            }

            // `didCompleteWithError:` releases the operation-queue slot asynchronously, so poll
            // briefly rather than asserting immediately after `cancel()` returns.
            var stillRunning = client.isRunning
            for _ in 0..<50 where stillRunning {
                try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
                stillRunning = client.isRunning
            }
            #expect(!stillRunning)
        }
    }
}

/// Test-only stand-in for the real client's own TLS challenge handling; see the identical
/// delegate in `RequestConfigurationURLSessionClientTests` (`RequestDLTests`) for why this exists
/// at all: `LocalServer` is always TLS-terminated with a throwaway self-signed certificate.
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

/// A bare TCP server that accepts a connection and never writes anything back -- used to keep a
/// request genuinely in flight so it can be cancelled mid-request, something `LocalServer` cannot
/// do, since it always answers immediately.
///
/// Not shared with `InternalsUnsafeTaskTests`'s own `withHangingServer(_:)`: that one drives
/// `Internals.Client` (AsyncHTTPClient), gated `#if canImport(NIOCore)`, via NIOCore's own
/// `ServerBootstrap`. This file tests `Internals.URLSessionClient` specifically and is gated only
/// on `canImport(Darwin)`, where Network.framework is always available, so it gets its own
/// Network.framework-backed implementation instead of needing NIOCore at all -- named distinctly
/// to avoid a module-level name collision with the other one when both happen to compile.
private func withHangingURLSessionTestServer<Result>(
    _ body: (Int) async throws -> Result
) async throws -> Result {
    let listener = try NWListener(using: .tcp, on: .any)
    let queue = DispatchQueue(label: "com.requestdl.tests.hanging-server")

    listener.newConnectionHandler = { connection in
        // Deliberately never reads or writes: the client is left waiting for a response that
        // never comes, until the test cancels it.
        connection.start(queue: queue)
    }

    let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
        let box = HangingServerContinuationBox(continuation)

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                guard let port = listener.port?.rawValue else {
                    box.resume(throwing: MissingHangingServerPortError())
                    return
                }
                box.resume(returning: port)
            case .failed(let error):
                box.resume(throwing: error)
            default:
                break
            }
        }

        listener.start(queue: queue)
    }

    do {
        let result = try await body(Int(port))
        listener.cancel()
        return result
    } catch {
        listener.cancel()
        throw error
    }
}

private struct MissingHangingServerPortError: Swift.Error {}

/// Bridges `NWListener.stateUpdateHandler` (called repeatedly) to a `CheckedContinuation` (usable
/// exactly once): resumes on the first `.ready`/`.failed`, ignores every later call. Mirrors
/// `RawTaskExecutorDispatchTests`'s own `RawServerContinuationBox` (`RequestDLTests`, not
/// reachable from this target).
private final class HangingServerContinuationBox: @unchecked Sendable {

    private let lock = Lock()
    private var continuation: CheckedContinuation<UInt16, Error>?

    init(_ continuation: CheckedContinuation<UInt16, Error>) {
        self.continuation = continuation
    }

    func resume(returning port: UInt16) { take()?.resume(returning: port) }
    func resume(throwing error: Error) { take()?.resume(throwing: error) }

    private func take() -> CheckedContinuation<UInt16, Error>? {
        lock.lock()
        defer { lock.unlock() }
        let continuation = self.continuation
        self.continuation = nil
        return continuation
    }
}

#endif
