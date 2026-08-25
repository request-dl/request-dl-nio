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

/// Streamed response-body downloads through
/// `Internals.URLSessionClient.execute(request:readingMode:delegate:)`, forced onto `.urlSession`
/// via `requireExecutor(_:)` directly at the `Internals` layer, the same way every other
/// `RequestConfigurationURLSessionClient*` suite in this file does.
///
/// Unlike the upload tests, there is no known issue here to work around: this uses
/// `session.dataTask(with:)` under the hood, not `uploadTask(withStreamedRequest:)`, so it never
/// triggers the resumable-uploads-draft auto-negotiation that made `LocalServer` hang for uploads
/// (see `RequestConfigurationURLSessionClientUploadTests.swift`'s type doc comment) -- and the existing
/// buffered `execute(request:delegate:)`, which is also backed by a plain data task, already
/// confirmed as much.
///
/// `Internals.DownloadBuffer` -- the exact same type `Internals.Session.execute(...)` builds for
/// the NIO backend -- is reused verbatim rather than reimplemented (it consumes
/// `Internals.AnyBuffer`, not a NIO `ByteBuffer`, so it was already transport-agnostic). That
/// reuse is why the tests below assert **exact** chunk boundaries for `.length` mode, stronger
/// than the acceptance note's minimum bar ("final assembled data and total byte counts match, not
/// exact chunk boundaries") -- `DownloadBuffer`'s own re-slicing guarantee doesn't depend on how
/// its *input* happened to be fragmented, so it should hold across executors, not just on NIO;
/// these tests are what confirm that design assumption rather than just asserting the loosest
/// possible bar.
struct RequestConfigurationURLSessionClientDownloadTests {

    @Test
    func urlSessionClient_whenStreamingDownload_deliversWholeBodyInExactLengthChunks() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = String(repeating: "abcdefghij", count: 10_000)
        let length = 1_024

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let resolved = try await resolve(
            TestProperty {
                BaseURL(localServer.baseURL)
                Path(uri)

                Session.localServer
                ReadingMode(length: length)
            }
        )

        // When
        try resolved.session.configuration.requireExecutor(.urlSession)

        let request = try resolved.requestConfiguration.buildURLRequestWithoutBody()

        let client = try Internals.URLSessionClient(configuration: .ephemeral)
        let step = try await client.execute(
            request: request,
            readingMode: resolved.requestConfiguration.readingMode,
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then
        #expect(step.head.status.code == 200)

        var chunks: [Data] = []
        for try await chunk in step.bytes {
            chunks.append(chunk)
        }

        let assembled = chunks.reduce(Data(), +)

        // `step.bytes.totalSize` comes from the response's own `Content-Length`, which
        // `LocalServer` sets to the size of the envelope it actually sends (`HTTPResult`'s
        // `{"receivedBytes":...,"response":...}`, built server-side from what it received on the
        // request), not `response.data.count` -- the size of just the configured "response" field
        // this test set up. Comparing against what was actually assembled here is what proves
        // `totalSize` and the real transfer agree, not a fixture-shaped coincidence.
        #expect(step.bytes.totalSize == assembled.count)

        let decoded = try HTTPResult<String>(assembled)
        #expect(decoded.response == output)

        #expect(chunks.dropLast().allSatisfy { $0.count == length })
        #expect((chunks.last?.count ?? .zero) <= length)
    }

    @Test
    func urlSessionClient_whenStreamingDownload_splitsOnSeparatorAcrossChunkBoundaries() async throws {
        // Given -- a payload sized so the separator (`,`) straddles wherever URLSession happens
        // to slice `didReceive data:` calls, exercising `Internals.DownloadBuffer`'s rolling
        // window (see its own doc comment) with real, executor-determined arrival boundaries
        // instead of ones a test controls directly.
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let fields = (0..<5_000).map { "field\($0)" }
        let output = fields.joined(separator: ",")

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let resolved = try await resolve(
            TestProperty {
                BaseURL(localServer.baseURL)
                Path(uri)

                Session.localServer
                ReadingMode(separator: ",")
            }
        )

        // When
        try resolved.session.configuration.requireExecutor(.urlSession)

        let request = try resolved.requestConfiguration.buildURLRequestWithoutBody()

        let client = try Internals.URLSessionClient(configuration: .ephemeral)
        let step = try await client.execute(
            request: request,
            readingMode: resolved.requestConfiguration.readingMode,
            delegate: AcceptAnyServerTrustDelegate()
        )

        // Then
        var chunks: [Data] = []
        for try await chunk in step.bytes {
            chunks.append(chunk)
        }

        let assembled = chunks.reduce(Data(), +)

        let decoded = try HTTPResult<String>(assembled)
        #expect(decoded.response == output)

        // Every chunk but a possible last remainder ends with the separator -- proves the
        // rechunking actually happened along `,` boundaries, not just that concatenation works.
        // (The `HTTPResult` envelope itself adds exactly one more `,` between its own fields, so
        // this holds for the whole wire payload, not just the `output` field inside it.)
        let separatorByte = Data(",".utf8)
        #expect(chunks.dropLast().allSatisfy { $0.suffix(1) == separatorByte })
    }

    /// A refused redirect fires before any response ever reaches
    /// `didReceive response:completionHandler:` for the *destination* -- it's the redirect
    /// itself `willPerformHTTPRedirection` refuses, so `redirectError` has to be checked in
    /// `resolveHead(with:downloadBuffer:)`, not just in the buffered/streamed-upload paths'
    /// `didCompleteWithError:`. This is what proves that wiring, not just that redirects work at
    /// all (already covered for the other two `execute` overloads by
    /// `InternalsURLSessionClientRedirectTests`, which shares the same `TaskDelegate` code path).
    @Test
    func urlSessionClient_whenRedirectChainExceedsMax_throwsBeforeYieldingAStep() async throws {
        // Given -- two redirects (origin -> hop -> destination) against a client only willing to
        // follow one.
        let localServer = try await LocalServer(.standard)
        let origin = "/" + UUID().uuidString
        let hop = "/" + UUID().uuidString
        let destination = "/" + UUID().uuidString

        localServer.cleanup(at: origin)
        localServer.cleanup(at: hop)
        localServer.cleanup(at: destination)

        localServer.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": hop], data: Data()),
            at: origin
        )
        localServer.insert(
            LocalServer.ResponseConfiguration(status: .found, headers: ["Location": destination], data: Data()),
            at: hop
        )
        localServer.insert(
            try LocalServer.ResponseConfiguration(jsonObject: "unreachable"),
            at: destination
        )

        defer {
            localServer.cleanup(at: origin)
            localServer.cleanup(at: hop)
            localServer.cleanup(at: destination)
        }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(origin)"))
        let client = try Internals.URLSessionClient(
            configuration: .ephemeral,
            redirectConfiguration: .follow(max: 1, allowCycles: false)
        )

        // When
        do {
            _ = try await client.execute(
                request: URLRequest(url: url),
                readingMode: .length(1_024),
                delegate: AcceptAnyServerTrustDelegate()
            )
            Issue.record("Not expecting success")
        } catch is Internals.URLSessionClient.RedirectLimitReachedError {
            // Then -- expected
        }
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

#endif
