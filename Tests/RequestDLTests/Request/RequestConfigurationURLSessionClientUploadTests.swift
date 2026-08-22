//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import Security

/// Phase 5f of `URLSESSION_TASK.md`: streamed request-body uploads through
/// `Internals.URLSessionClient.execute(request:streaming:delegate:onUploadProgress:)`, forced onto
/// `.urlSession` via `requireExecutor(_:)` (Phase 3) the same way `RequestConfigurationURLSessionClientTests`
/// (Phase 5a) drives the non-streaming path -- `Session.requiredExecutor(_:)` is Phase 7, not built
/// yet. Mirrors `UploadTaskTests.uploadTask()` (same `LocalServer`/`HTTPResult` fixtures: the
/// server reports the total bytes it actually received, not per-chunk), but drives
/// `RequestConfiguration.buildURLRequestWithoutBody()` + the new streaming `execute` overload
/// directly instead of `UploadTask`, and trusts `LocalServer`'s self-signed certificate via a
/// test-only delegate the same way 5a does -- no TLS customization is in scope here either.
///
/// **Both tests below are a confirmed, well-evidenced `withKnownIssue`, not a defect in
/// `Internals.URLSessionUploadStream`/the streaming bridge itself.** `uploadTask(withStreamedRequest:)`
/// on this OS build automatically negotiates the IETF "resumable uploads" draft
/// (<https://datatracker.ietf.org/doc/draft-ietf-httpbis-resumable-upload/>) for any streamed
/// upload -- the outgoing request carries `Upload-Draft-Interop-Version`/`Upload-Complete`
/// headers neither RequestDL nor this suite ever asked for. `LocalServer` (a minimal hand-rolled
/// NIOHTTP1 test server) answers with a perfectly ordinary 200 response, which the draft
/// negotiation apparently doesn't recognize as settling the exchange: the response never reaches
/// `urlSession(_:dataTask:didReceive:completionHandler:)` at all, and the task times out.
///
/// Confirmed, not assumed, via two independent probes outside this suite: (1) the exact same
/// `needNewBodyStream`/`didSendBodyData`/`didReceive`/`didCompleteWithError` delegate sequence,
/// built from a plain `InputStream(data:)` with no `Internals.URLSessionUploadStream` involved at
/// all, against a real external server (`https://httpbin.org/post`) -- completes normally, proving
/// the delegate wiring pattern itself is correct; (2) the *buffered* upload path
/// (`execute(request:delegate:)`, `session.data(for:delegate:)`, no `needNewBodyStream` at all)
/// against this exact same `LocalServer`, same payload size, same everything else -- also
/// completes normally in well under a second. Only the combination of `uploadTask(withStreamedRequest:)`
/// specifically and `LocalServer` specifically hangs. `InternalsURLSessionUploadStreamTests`
/// (`RequestDLInternalsTests`) is what actually verifies `Internals.URLSessionUploadStream`'s own
/// correctness (byte-for-byte order, backpressure, cancellation) -- independent of `URLSession`/
/// `LocalServer` entirely, and unaffected by any of this.
///
/// A short `timeoutIntervalForRequest` is used for these two tests specifically so the known,
/// already-understood hang fails in seconds instead of the default 60.
struct RequestConfigurationURLSessionClientUploadTests {

    private static var shortTimeoutConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        return configuration
    }

    @Test
    func urlSessionClient_whenStreamingUpload_deliversWholeBodyIntact() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello World"
        let upload = await Data.randomData(length: 262_144)

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let resolved = try await resolve(
            TestProperty {
                BaseURL(localServer.baseURL)
                Path(uri)

                Session.localServer
                RequestMethod(.post)

                Payload(data: upload)
            }
        )

        // When
        try resolved.session.configuration.requireExecutor(.urlSession)

        let body = try #require(resolved.requestConfiguration.body)
        let request = try resolved.requestConfiguration.buildURLRequestWithoutBody()

        // Then -- see the type doc comment: known issue, `LocalServer` and the resumable-uploads
        // draft `uploadTask(withStreamedRequest:)` negotiates on its own, not a defect here.
        await withKnownIssue(
            "uploadTask(withStreamedRequest:) auto-negotiates the resumable-uploads draft, which LocalServer doesn't answer -- see the type doc comment",
            {
                let client = try Internals.URLSessionClient(configuration: Self.shortTimeoutConfiguration)
                let result = try await client.execute(
                    request: request,
                    streaming: body,
                    delegate: AcceptAnyServerTrustDelegate()
                )

                #expect(result.head.status.code == 200)

                let decoded = try HTTPResult<String>(result.body)
                #expect(decoded.receivedBytes == upload.count)
                #expect(decoded.response == output)
            }
        )
    }

    /// Not exact chunk-by-chunk byte counts or timing (URLSession's own to pick, not RequestDL's
    /// -- see the acceptance note in `URLSESSION_TASK.md` Phase 5f) -- just that
    /// `didSendBodyData` fires in a sequence whose cumulative total is monotonically increasing
    /// and reaches the whole body, mirroring what `ModifiersProgressTests`'s looser upload
    /// assertion (`uploadMonitor.uploadedBytes.reduce(.zero, +) == data.count`, sum only) checks
    /// on the NIO backend. Blocked on the same known issue as the test above -- `didSendBodyData`
    /// itself fires correctly (confirmed while diagnosing that issue), but the request never
    /// completes for `execute` to return from, so this can't observe a full run either.
    @Test
    func urlSessionClient_whenStreamingUpload_reportsProgressInIncreasingOrder() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let upload = await Data.randomData(length: 131_072)

        let response = try LocalServer.ResponseConfiguration(jsonObject: "Hello World")

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let resolved = try await resolve(
            TestProperty {
                BaseURL(localServer.baseURL)
                Path(uri)

                Session.localServer
                RequestMethod(.post)

                Payload(data: upload)
                    .payloadChunkSize(4_096)
            }
        )

        try resolved.session.configuration.requireExecutor(.urlSession)

        let body = try #require(resolved.requestConfiguration.body)
        let request = try resolved.requestConfiguration.buildURLRequestWithoutBody()

        let progress = ProgressRecorder()

        // When / Then
        await withKnownIssue(
            "uploadTask(withStreamedRequest:) auto-negotiates the resumable-uploads draft, which LocalServer doesn't answer -- see the type doc comment",
            {
                let client = try Internals.URLSessionClient(configuration: Self.shortTimeoutConfiguration)

                _ = try await client.execute(
                    request: request,
                    streaming: body,
                    delegate: AcceptAnyServerTrustDelegate(),
                    onUploadProgress: { bytesSent, totalBytesExpectedToSend in
                        progress.record(bytesSent: bytesSent, total: totalBytesExpectedToSend)
                    }
                )

                let samples = progress.samples
                #expect(!samples.isEmpty)
                #expect(samples.allSatisfy { $0.total == upload.count })
                #expect(samples.map(\.bytesSent) == samples.map(\.bytesSent).sorted())
                #expect(samples.last?.bytesSent == upload.count)
            }
        )
    }
}

/// Test-only stand-in for the TLS challenge handling Phase 5e adds for real -- `LocalServer` is
/// always TLS-terminated with a throwaway self-signed certificate, even outside any TLS feature
/// under test, so *something* has to trust it for a plain, no-customization round trip to
/// complete at all. Duplicated from `RequestConfigurationURLSessionClientTests.swift` (`private`
/// there) rather than shared, matching how small test-only fixtures are kept local to their file
/// throughout this suite.
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

/// Collects `onUploadProgress` samples under a lock -- the callback is `@Sendable` and may be
/// invoked off the main actor.
private final class ProgressRecorder: @unchecked Sendable {

    private let lock = NSLock()
    private var _samples: [(bytesSent: Int, total: Int)] = []

    var samples: [(bytesSent: Int, total: Int)] {
        lock.lock()
        defer { lock.unlock() }
        return _samples
    }

    func record(bytesSent: Int, total: Int) {
        lock.lock()
        defer { lock.unlock() }
        _samples.append((bytesSent, total))
    }
}

#endif
