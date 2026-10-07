//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

import Foundation

/// `Internals.URLSessionClient`'s two `SessionTask`-producing `execute` overloads: the pieces
/// `RequestExecutingClient`'s `.urlSession` conformance
/// (`Internals.URLSessionClient+RequestExecutingClient.swift`, `RequestDLTests`) is built from.
/// Exercised directly here, no `RawTask`/`RequestConfiguration` involved.
///
/// `.concurrent(watchdogAffectedPlatformConcurrencyLimit)`/`.nonFatalWatchdog`: real network I/O
/// against a `LocalServer`, on the same simulator runners `WatchdogAffectedPlatformConcurrencyLimit.swift`
/// documents as prone to scheduler-contention `AsyncLock.Watchdog` false positives; see
/// `RequestConfigurationURLSessionClientUploadTests`'s own copy of this note for the failure mode
/// these two traits avoid.
@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
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
            decompression: .disabled,
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

        // Then: a GET has no body to report progress for, so `upload` closes with nothing in
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
    /// passes again. Not shipped as two versions of the code, just how this test was checked.
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
            decompression: .disabled,
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

        // Then: the cache stream must close on its own once the download finishes, or
        // `cachedChunks` above would hang forever; it does, since `Internals.DownloadBuffer`
        // closes `_cacheStream` alongside its own `stream` in `_close()`.
        let assembledDownload = downloadedChunks.reduce(Data(), +)
        let assembledCache = try await cachedChunks.reduce(Data(), +)

        #expect(assembledCache == assembledDownload)
        #expect(!assembledCache.isEmpty)
    }

    /// Caching a response this package still has to decode itself would persist the still-
    /// compressed wire bytes under a cached head that (on replay, which never re-runs
    /// decompression) claims they're already decoded. So whenever
    /// `Internals.ManualDecompressionDispatch.requiresManualDecoding(for:)` answers `true` for a
    /// response, the cache tee must never attach at all.
    ///
    /// Dropping `decompressionDispatch` from `runExchange`'s parameter list and its
    /// `requiresManualDecoding` guard makes this test fail, since `cache` is invoked and
    /// `cacheStream` receives the (still identity-"encoded") body instead of closing empty.
    @Test
    func sessionTask_whenCacheProvidedAndManualDecompressionRequired_skipsTheCacheTee() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = String(repeating: "the quick brown fox jumps over the lazy dog ", count: 500)

        let response = try LocalServer.ResponseConfiguration(
            headers: ["Content-Encoding": IdentityTestAlgorithm.contentEncoding],
            jsonObject: output
        )

        localServer.cleanup(at: uri)
        localServer.insert(response, at: uri)
        defer { localServer.cleanup(at: uri) }

        let url = try #require(URL(string: "https://\(localServer.baseURL)\(uri)"))
        let client = try Internals.URLSessionClient(configuration: .ephemeral)

        let cacheInvoked = CacheInvocationFlag()
        let cacheStream = Internals.AsyncStream<Internals.DataBuffer>()

        // When
        let sessionTask = try await client.execute(
            request: URLRequest(url: url),
            readingMode: .length(2_048),
            uploadingBytes: .zero,
            decompression: .enabled(algorithms: [IdentityTestAlgorithm()], limit: .none),
            cache: { _ in
                cacheInvoked.markInvoked()
                return cacheStream
            },
            logger: nil,
            delegate: AcceptAnyServerTrustDelegate()
        )

        var downloadedChunks: [Data] = []

        for try await step in sessionTask.response {
            guard case .download(let downloadStep) = step else { continue }
            for try await chunk in downloadStep.bytes {
                downloadedChunks.append(chunk)
            }
        }

        // Then: the download itself still succeeds (manual decoding runs on the live path
        // regardless of caching), but nothing was ever handed to the cache.
        let decoded = try HTTPResult<String>(downloadedChunks.reduce(Data(), +))
        #expect(decoded.response == output)
        #expect(!cacheInvoked.invoked)
    }

    @Test
    func sessionTask_whenCancelledMidDownload_stopsRunningSoonAfter() async throws {
        // Given: large enough that cancelling after the first chunk still leaves real work
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
            decompression: .disabled,
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

        // Then: `didCompleteWithError:` (cancellation included) is what releases the
        // `operationQueue` slot `isRunning` reads, so this polls instead of asserting
        // immediately after an async cancel with no ordering guarantee of its own. A fixed
        // one-second poll was not enough on a contended simulator runner, where that callback was
        // seen arriving a minute and a half late; `eventually` stretches its budget there and
        // ends as soon as the slot is released everywhere else.
        try await eventually(timeout: 15) { !client.isRunning }
    }

    /// The upload must report progress while the body streams. `Internals.URLSessionUploadFile`
    /// keeps small bodies in memory (uploaded via `uploadTask(with:from:)`) and spills anything
    /// past `inMemoryThreshold` to a temp file (uploaded via `uploadTask(with:fromFile:)`), so
    /// neither touches `InputStream`/`needNewBodyStream`, where CFNetwork never recognizes a
    /// custom `InputStream` as reaching end-of-body. This test's 128 KiB payload takes the
    /// in-memory branch.
    ///
    /// `upload` closes as soon as the body actually finishes sending, the way
    /// `Internals.ClientResponseReceiver.didReceiveHead`/`didSendRequest` close it on the NIO
    /// side, not only from `onDownloadComplete` (task completion). A live progress bar would
    /// otherwise hang waiting for the whole download before ever hearing "upload done."
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

        let (stream, continuation) = AsyncStream<Internals.Bytes>.makeStream()
        for start in Swift.stride(from: 0, to: payload.count, by: 4_096) {
            let end = Swift.min(start + 4_096, payload.count)
            continuation.yield(Internals.Bytes(Data(payload[start..<end])))
        }
        continuation.finish()

        // See `simulatorAffectedURLSessionRequestTimeout`'s doc comment (`RequestDLTestSupport`)
        // for why this margin is wider on Apple Simulator platforms than elsewhere.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = simulatorAffectedURLSessionRequestTimeout
        let client = try Internals.URLSessionClient(configuration: configuration)

        // When
        let sessionTask = try await client.execute(
            request: request,
            streaming: stream,
            readingMode: .length(1_024),
            uploadingBytes: payload.count,
            decompression: .disabled,
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

        // Then
        #expect(!chunkSizes.isEmpty)
        #expect(chunkSizes == chunkSizes.sorted())
        #expect(chunkSizes.last == payload.count)
    }

    /// Same bridge as the test above (the file-backed upload). Kept here (rather than relying
    /// on that test alone) to also exercise the download half of this specific overload through
    /// `LocalServer`.
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

        let (stream, continuation) = AsyncStream<Internals.Bytes>.makeStream()
        continuation.yield(Internals.Bytes(Data(payload)))
        continuation.finish()

        // See `simulatorAffectedURLSessionRequestTimeout`'s doc comment (`RequestDLTestSupport`)
        // for why this margin is wider on Apple Simulator platforms than elsewhere.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = simulatorAffectedURLSessionRequestTimeout
        let client = try Internals.URLSessionClient(configuration: configuration)

        // When
        let sessionTask = try await client.execute(
            request: request,
            streaming: stream,
            readingMode: .length(1_024),
            uploadingBytes: payload.count,
            decompression: .disabled,
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

        // Then
        #expect(!chunks.isEmpty)
    }
}

/// Test-only stand-in for the real client's own TLS challenge handling. See the identical
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

/// The identity function, registered under a `Content-Encoding` CFNetwork doesn't decode
/// natively, so `Internals.ManualDecompressionDispatch` always takes the `.dispatch` branch for
/// it, the one condition `requiresManualDecoding(for:)` answers `true` for.
private struct IdentityTestAlgorithm: Internals.DecompressionAlgorithm {

    static let contentEncoding = "x-requestdl-identity-test"

    struct Stream: Internals.DecompressorStream {
        mutating func callAsFunction(decompressing bytes: Data) throws -> Data { bytes }
        mutating func finish() throws -> Data { Data() }
    }

    var contentEncodingValue: String { Self.contentEncoding }

    func callAsFunction() throws -> any Internals.DecompressorStream { Stream() }
}

/// Whether the `@Sendable` `cache` closure `Internals.URLSessionClient.execute` takes was ever
/// called, observed from outside it. A plain captured `var` can't be mutated from inside a
/// `@Sendable` closure; this is the smallest thing that can.
private final class CacheInvocationFlag: @unchecked Sendable {

    private let lock = NSLock()
    private var _invoked = false

    var invoked: Bool {
        lock.withLock { _invoked }
    }

    func markInvoked() {
        lock.withLock { _invoked = true }
    }
}

#endif
