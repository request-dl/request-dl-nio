//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import SwiftAsyncStream
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation
import Security

/// Streamed request-body uploads through
/// `Internals.URLSessionClient.execute(request:streaming:delegate:onUploadProgress:)`, forced onto
/// `.urlSession` via `requireExecutor(_:)` directly at the `Internals` layer, the same way
/// `RequestConfigurationURLSessionClientTests` drives the non-streaming path. Mirrors
/// `UploadTaskTests.uploadTask()` (same `LocalServer`/`HTTPResult` fixtures: the server reports
/// the total bytes it actually received, not per-chunk), but drives
/// `RequestConfiguration.buildURLRequestWithoutBody()` + the streaming `execute` overload directly
/// instead of `UploadTask`, and trusts `LocalServer`'s self-signed certificate via a test-only
/// delegate the same way the non-streaming suite does -- no TLS customization is in scope here
/// either.
///
/// **Both tests below used to be a confirmed `withKnownIssue`** -- the original bridge
/// (`Internals.URLSessionUploadStream`, an `InputStream` subclass) drove
/// `uploadTask(withStreamedRequest:)`, which on this OS build automatically negotiates the IETF
/// "resumable uploads" draft for any streamed upload, and a from-scratch investigation confirmed
/// the real cause runs deeper than that draft negotiation alone: no custom `InputStream` -- a
/// Swift subclass or a genuine `CFReadStream` -- is ever recognized by CFNetwork as reaching
/// end-of-body, on `LocalServer`, two independent HTTP/2 servers, and `https://httpbin.org/post`
/// alike. Every callback-level hypothesis (`copyProperty`/`setProperty`, `getBuffer`,
/// object-identity) was ruled out without finding the mechanism. `Internals.URLSessionUploadFile`
/// works around it instead of fixing it: it drains `body` and this now drives
/// `uploadTask(with:from:)` (small bodies, kept in memory) or
/// `uploadTask(with:fromFile:)` (anything past `Internals.URLSessionUploadFile.inMemoryThreshold`,
/// spilled to a temporary file) -- both completely different `URLSession` code paths that never
/// touch `InputStream`/`needNewBodyStream` (or the resumable-uploads draft) at all. Both payloads
/// in `urlSessionClient_whenStreamingUpload...` below (256 KiB, 128 KiB) sit comfortably under
/// that threshold, so those two tests specifically exercise the in-memory branch;
/// `InternalsURLSessionUploadFileTests` (`RequestDLInternalsTests`) covers the file-spillover
/// branch directly, without a real network round trip. A third shape -- a `Payload(url:)` body
/// that's already sitting in a file untouched, forwarded as `existingUploadFile` rather than
/// drained at all (a same-day refinement past the memory/disk split, to avoid a redundant copy
/// of a file that's already exactly right) -- is exercised by
/// `urlSessionClient_whenStreamingUploadFromExistingFile_deliversWholeBodyIntact`.
///
/// A short `timeoutIntervalForRequest` is kept on these tests -- harmless now that they pass, and
/// cheap insurance against a future regression hanging the suite for the default 60s instead of
/// failing fast. 30s, not tighter: CI's iOS/iPadOS/watchOS/visionOS Simulator runners are visibly
/// slower under load than a local run or macOS's own (host-speed) job in the same workflow --
/// confirmed directly, a genuine `NSURLErrorTimedOut` still surfaced here at a 15s margin under
/// severe contention across two separate platforms in the same CI run. Still tight enough to fail
/// fast on a real regression, loose enough not to flake under normal contention.
///
/// `.concurrent(watchdogAffectedPlatformConcurrencyLimit)`/`.nonFatalWatchdog`: real network I/O
/// against a `LocalServer`, on the same simulator runners `WatchdogAffectedPlatformConcurrencyLimit.swift`
/// documents as prone to scheduler-contention `AsyncLock.Watchdog` false positives -- without
/// these, a stall elsewhere in the same job (this suite adding to the unthrottled concurrent load)
/// can trip a watchdog fatally and crash the whole test process mid-run, taking every other
/// in-flight test down with it, rather than surfacing as this suite's own (real, informative)
/// timeout.
@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct RequestConfigurationURLSessionClientUploadTests {

    private static var shortTimeoutConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
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

        // Then
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

    /// The other half of the refinement described in the type doc comment: a `Payload(url:)`
    /// body is backed by exactly one unread, non-temporary `Internals.FileBuffer`, so
    /// `RequestBody.wholeFileURL` resolves to the fixture file itself and
    /// `Internals.URLSessionClient+RequestExecutingClient.swift` passes it straight through as
    /// `existingUploadFile` -- exercised directly here (rather than only at the `RequestBody`
    /// unit-test level, `RequestBodyBuildingTests`) so a real round trip confirms the shortcut
    /// still delivers the exact right bytes, not just that the URL gets forwarded correctly.
    @Test
    func urlSessionClient_whenStreamingUploadFromExistingFile_deliversWholeBodyIntact() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = "Hello World"
        let upload = await Data.randomData(length: 262_144)

        let fileURL =
            temporaryDirectoryURL
            .appendingPathComponent("existingUploadFile.\(UUID())")
            .appendingPathExtension("raw")
        try await fileURL.createPathIfNeeded()
        defer { fileURL.scheduleRemoval() }
        try upload.write(to: fileURL)

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

                Payload(url: fileURL, contentType: .octetStream)
            }
        )

        // When
        try resolved.session.configuration.requireExecutor(.urlSession)

        let body = try #require(resolved.requestConfiguration.body)
        let request = try resolved.requestConfiguration.buildURLRequestWithoutBody()

        // This is the assertion that makes the rest of the test meaningful: confirms the fixture
        // above genuinely qualifies for the shortcut, not just that the round trip below happens
        // to work regardless of which path it took.
        #expect(body.wholeFileURL == fileURL)

        // Then
        let client = try Internals.URLSessionClient(configuration: Self.shortTimeoutConfiguration)
        let result = try await client.execute(
            request: request,
            streaming: body,
            delegate: AcceptAnyServerTrustDelegate(),
            existingUploadFile: body.wholeFileURL
        )

        #expect(result.head.status.code == 200)

        let decoded = try HTTPResult<String>(result.body)
        #expect(decoded.receivedBytes == upload.count)
        #expect(decoded.response == output)

        // The fixture file must survive the upload untouched -- unlike `.file`, `.existingFile`
        // is never this package's to remove.
        #expect(await fileURL.isReachable)
    }

    /// Not exact chunk-by-chunk byte counts or timing (URLSession's own to pick, not RequestDL's)
    /// -- just that `didSendBodyData` fires in a sequence whose cumulative total is monotonically
    /// increasing and reaches the whole body, mirroring what `ModifiersProgressTests`'s looser
    /// upload assertion (`uploadMonitor.uploadedBytes.reduce(.zero, +) == data.count`, sum only)
    /// checks on the NIO backend. `uploadTask(with:fromFile:)` still fires `didSendBodyData` the
    /// same way a streamed upload would, so this observes it the same way originally intended,
    /// even though the file-backed bridge is what actually drives it now, not the
    /// `InputStream`-based one.
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

        // When
        let client = try Internals.URLSessionClient(configuration: Self.shortTimeoutConfiguration)

        _ = try await client.execute(
            request: request,
            streaming: body,
            delegate: AcceptAnyServerTrustDelegate(),
            onUploadProgress: { bytesSent, totalBytesExpectedToSend in
                progress.record(bytesSent: bytesSent, total: totalBytesExpectedToSend)
            }
        )

        // Then
        let samples = progress.samples
        #expect(!samples.isEmpty)
        #expect(samples.allSatisfy { $0.total == upload.count })
        #expect(samples.map(\.bytesSent) == samples.map(\.bytesSent).sorted())
        #expect(samples.last?.bytesSent == upload.count)
    }
}

/// Test-only stand-in for the real client's own TLS challenge handling -- `LocalServer` is
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

    private let lock = Lock()
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
