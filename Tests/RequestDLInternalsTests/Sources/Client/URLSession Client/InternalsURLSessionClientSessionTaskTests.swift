//
// See LICENSE for this package's licensing information.
//

import NIOCore
import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation

/// Phase 7b2 of `URLSESSION_TASK.md`: `Internals.URLSessionClient`'s two `SessionTask`-producing
/// `execute` overloads -- the pieces `RequestExecutingClient`'s `.urlSession` conformance
/// (`Internals.URLSessionClient+RequestExecutingClient.swift`, `RequestDLTests`) is built from.
/// Exercised directly here, no `RawTask`/`RequestConfiguration` involved (that's 7b3).
struct InternalsURLSessionClientSessionTaskTests {

    @Test
    func sessionTask_whenExecutingNonStreamingRequest_deliversWholeBodyIntact() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = String(repeating: "abcdefghij", count: 10_000)
        let length = 1_024

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(configuration: .ephemeral)

        // When
        let sessionTask = try await client.execute(
            request: URLRequest(url: url),
            readingMode: .length(length),
            uploadingBytes: .zero,
            cache: nil,
            logger: nil,
            delegate: AcceptAnyServerTrustDelegate()
        )

        var uploadSteps: [Internals.UploadStep] = []
        var chunks: [Data] = []

        for try await step in sessionTask.response {
            switch step {
            case .upload(let uploadStep):
                uploadSteps.append(uploadStep)
            case .download(let downloadStep):
                #expect(downloadStep.head.status.code == 200)
                for try await chunk in downloadStep.bytes {
                    chunks.append(chunk)
                }
            }
        }

        // Then -- a GET has no body to report progress for, so `upload` closes with nothing in
        // it, same as the NIO backend's own bodyless-request behavior.
        #expect(uploadSteps.isEmpty)

        let assembled = chunks.reduce(Data(), +)
        let decoded = try HTTPResult<String>(assembled)
        #expect(decoded.response == output)
        #expect(chunks.dropLast().allSatisfy { $0.count == length })
    }

    /// Mirrors `InternalsURLSessionClientCookieTests`'s own discipline for proving a test isn't
    /// tautological: verified by temporarily removing the `downloadBuffer.cacheStream(cacheStream)`
    /// call this test depends on and confirming it fails, then restoring it and confirming it
    /// passes again -- not shipped as two versions of the code, just how this test was checked.
    @Test
    func sessionTask_whenCacheProvided_teesDownloadedChunksToCache() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = String(repeating: "the quick brown fox jumps over the lazy dog ", count: 500)

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(configuration: .ephemeral)

        let cacheStream = Internals.AsyncStream<Internals.DataBuffer>()

        // When
        let sessionTask = try await client.execute(
            request: URLRequest(url: url),
            readingMode: .length(2_048),
            uploadingBytes: .zero,
            cache: { _ in cacheStream },
            logger: nil,
            delegate: AcceptAnyServerTrustDelegate()
        )

        async let cachedChunks: [Data] = {
            var chunks: [Data] = []
            for try await buffer in cacheStream {
                var buffer = buffer
                if let data = await buffer.readData(buffer.readableBytes) {
                    chunks.append(data)
                }
            }
            return chunks
        }()

        var downloadedChunks: [Data] = []

        for try await step in sessionTask.response {
            guard case .download(let downloadStep) = step else { continue }
            for try await chunk in downloadStep.bytes {
                downloadedChunks.append(chunk)
            }
        }

        // Then -- the cache stream must close on its own once the download finishes, or
        // `cachedChunks` above would hang forever; it does, since `Internals.DownloadBuffer`
        // closes `_cacheStream` alongside its own `stream` in `_close()`.
        let assembledDownload = downloadedChunks.reduce(Data(), +)
        let assembledCache = try await cachedChunks.reduce(Data(), +)

        #expect(assembledCache == assembledDownload)
        #expect(!assembledCache.isEmpty)
    }

    @Test
    func sessionTask_whenCancelledMidDownload_stopsRunningSoonAfter() async throws {
        // Given -- large enough that cancelling after the first chunk still leaves real work
        // in flight for cancellation to actually interrupt, not race a download that already
        // finished.
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = String(repeating: "abcdefghij", count: 200_000)

        let response = try LocalServer.ResponseConfiguration(jsonObject: output)

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(configuration: .ephemeral)

        // When
        let sessionTask = try await client.execute(
            request: URLRequest(url: url),
            readingMode: .length(1_024),
            uploadingBytes: .zero,
            cache: nil,
            logger: nil,
            delegate: AcceptAnyServerTrustDelegate()
        )

        #expect(client.isRunning)

        for try await step in sessionTask.response {
            guard case .download(let downloadStep) = step else { continue }
            for try await _ in downloadStep.bytes {
                break
            }
            break
        }

        sessionTask.seed()

        // Then -- `didCompleteWithError:` (cancellation included) is what releases the
        // `operationQueue` slot `isRunning` reads, so this polls briefly instead of asserting
        // immediately after an async cancel with no ordering guarantee of its own.
        var stillRunning = client.isRunning
        for _ in 0..<50 where stillRunning {
            try await _Concurrency.Task.sleep(nanoseconds: 20_000_000)
            stillRunning = client.isRunning
        }

        #expect(!stillRunning)
    }

    /// **A confirmed `withKnownIssue`, not a separable case** -- the first version of this test
    /// tried to dodge `LocalServer`'s known `uploadTask(withStreamedRequest:)` incompatibility
    /// (see `RequestConfigurationURLSessionClientUploadTests`'s type doc comment) by only
    /// consuming `.upload(_:)` steps and stopping before ever awaiting a `.download(_:)` one, on
    /// the assumption that upload finishing before a response is expected would keep this clear
    /// of the hang. Run, not just reasoned about: it still failed, because
    /// `Internals.AsyncResponse.Iterator.next()` decides "no more uploads, move to download" and
    /// *starts draining `head` for the response* inside the very same call to `next()` that would
    /// otherwise yield "nothing more" -- there is no `.upload(_:)` step a caller can stop at
    /// that's guaranteed to return before that drain begins, so the loop above blocks on the
    /// exact same head resolution the "completes" test below already documents as hung. Diagnosing
    /// this *did* find one genuine bug, fixed separately in `executeSessionTask`: `upload` was
    /// only closing from `onDownloadComplete` (task completion), not as soon as the body actually
    /// finished sending the way `Internals.ClientResponseReceiver.didReceiveHead`/`didSendRequest`
    /// close it on the NIO side -- a live progress bar against a *working* server would have hung
    /// waiting for the whole download before ever hearing "upload done." That fix is real and
    /// stays; it just doesn't change this test's outcome, since here `headCompletion` itself never
    /// resolves until the 5s timeout either way.
    @Test
    func sessionTask_whenStreamingUploadAndDownload_reportsUploadProgressInIncreasingOrder() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let payload = await Data.randomData(length: 131_072)

        let response = try LocalServer.ResponseConfiguration(jsonObject: "Hello World")

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        var request = URLRequest(url: try #require(URL(string: "https://\(localServer.baseURL)\(uri)")))
        request.httpMethod = "POST"

        let (stream, continuation) = AsyncStream<ByteBuffer>.makeStream()
        for start in Swift.stride(from: 0, to: payload.count, by: 4_096) {
            let end = Swift.min(start + 4_096, payload.count)
            continuation.yield(ByteBuffer(bytes: payload[start..<end]))
        }
        continuation.finish()

        var configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        let client = try Internals.URLSessionClient(configuration: configuration)

        // When / Then -- see the doc comment above: known issue, confirmed by actually running
        // the "clever" workaround first and watching it fail the same way.
        await withKnownIssue(
            "uploadTask(withStreamedRequest:) auto-negotiates the resumable-uploads draft, which LocalServer doesn't answer -- see RequestConfigurationURLSessionClientUploadTests's type doc comment",
            {
                let sessionTask = try await client.execute(
                    request: request,
                    streaming: stream,
                    readingMode: .length(1_024),
                    uploadingBytes: payload.count,
                    cache: nil,
                    logger: nil,
                    delegate: AcceptAnyServerTrustDelegate()
                )

                var chunkSizes: [Int] = []

                for try await step in sessionTask.response {
                    guard case .upload(let uploadStep) = step else { break }
                    chunkSizes.append(uploadStep.chunkSize)
                    #expect(uploadStep.totalSize == payload.count)
                }

                #expect(!chunkSizes.isEmpty)
                #expect(chunkSizes == chunkSizes.sorted())
                #expect(chunkSizes.last == payload.count)
            }
        )
    }

    /// Confirmed, well-evidenced `withKnownIssue`, same root cause `RequestConfigurationURLSessionClientUploadTests`
    /// documents in full: `uploadTask(withStreamedRequest:)` auto-negotiates the resumable-uploads
    /// draft against any server, and `LocalServer` never answers it, so the response never
    /// arrives. Kept here (rather than relying on the test above alone) to also exercise the
    /// download half of this specific overload -- unreachable via `LocalServer` today, same as
    /// upstream, but worth re-checking automatically once that gap closes.
    @Test
    func sessionTask_whenStreamingUploadAndDownloadCompletes_deliversWholeBodyIntact() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let payload = await Data.randomData(length: 4_096)

        let response = try LocalServer.ResponseConfiguration(jsonObject: "Hello World")

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        var request = URLRequest(url: try #require(URL(string: "https://\(localServer.baseURL)\(uri)")))
        request.httpMethod = "POST"

        let (stream, continuation) = AsyncStream<ByteBuffer>.makeStream()
        continuation.yield(ByteBuffer(bytes: payload))
        continuation.finish()

        var configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5
        let client = try Internals.URLSessionClient(configuration: configuration)

        // When / Then
        await withKnownIssue(
            "uploadTask(withStreamedRequest:) auto-negotiates the resumable-uploads draft, which LocalServer doesn't answer -- see RequestConfigurationURLSessionClientUploadTests's type doc comment",
            {
                let sessionTask = try await client.execute(
                    request: request,
                    streaming: stream,
                    readingMode: .length(1_024),
                    uploadingBytes: payload.count,
                    cache: nil,
                    logger: nil,
                    delegate: AcceptAnyServerTrustDelegate()
                )

                var chunks: [Data] = []

                for try await step in sessionTask.response {
                    guard case .download(let downloadStep) = step else { continue }
                    for try await chunk in downloadStep.bytes {
                        chunks.append(chunk)
                    }
                }

                #expect(!chunks.isEmpty)
            }
        )
    }
}

/// Test-only stand-in for the TLS challenge handling Phase 5e adds for real -- see the identical
/// delegate elsewhere in this suite for why this exists at all: `LocalServer` is always
/// TLS-terminated with a throwaway self-signed certificate.
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
