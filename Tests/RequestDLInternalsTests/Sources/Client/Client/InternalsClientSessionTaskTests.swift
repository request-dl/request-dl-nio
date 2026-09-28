//
// See LICENSE for this package's licensing information.
//

// `Internals.Client`'s `SessionTask`-producing `execute` overload: the NIO counterpart to
// `InternalsURLSessionClientSessionTaskTests`, mirroring its cache-tee coverage so a regression
// like the one this file's `whenCacheProvidedAndManualDecompressionRequired_skipsTheCacheTee` guards
// against (found while merging the `.nio` and `.urlSession` back-pressure fixes together: the
// `.urlSession` rewrite dropped `decompressionDispatch` off `runExchange`'s parameter list, silently
// undoing the cache/manual-decompression gate `Internals.CacheControl`'s own audit fix added) can't
// slip through unnoticed on either executor again.
#if canImport(NIOCore)

import AsyncHTTPClient
import NIOCore
import Testing

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
#endif

@testable import RequestDLInternals
@testable import RequestDLTestSupport

/// The identity function, registered under a `Content-Encoding` neither executor decodes
/// natively, so `Internals.ManualDecompressionDispatch` always takes the `.dispatch` branch for
/// it -- the one condition `requiresManualDecoding(for:)` answers `true` for.
private struct IdentityTestAlgorithm: Internals.DecompressionAlgorithm {

    static let contentEncoding = "x-requestdl-identity-test"

    struct Stream: Internals.DecompressorStream {
        mutating func callAsFunction(decompressing bytes: Data) throws -> Data { bytes }
        mutating func finish() throws -> Data { Data() }
    }

    var contentEncodingValue: String { Self.contentEncoding }

    func callAsFunction() throws -> any Internals.DecompressorStream { Stream() }
}

@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsClientSessionTaskTests {

    private func makeSession(decompression: Internals.Decompression = .disabled) -> Internals.Session {
        var configuration = Internals.Session.Configuration()
        var secureConnection = Internals.SecureConnection()

        secureConnection.certificateVerification = .some(.none)
        configuration.secureConnection = secureConnection
        configuration.decompression = decompression
        configuration.timeout.connect = 60_000_000_000

        return Internals.Session(
            provider: .identified("com.requestdl.tests.client-session-task-\(UUID())", numberOfThreads: 1),
            configuration: configuration
        )
    }

    @Test
    func whenCacheProvided_teesDownloadedChunksToCache() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = String(repeating: "the quick brown fox jumps over the lazy dog ", count: 500)

        localServer.insert(try LocalServer.ResponseConfiguration(jsonObject: output), at: uri)
        defer { localServer.cleanup(at: uri) }

        let session = makeSession()
        let client = try await session.client()
        let urlString = "https://\(localServer.baseURL)\(uri)"
        let request = try HTTPClient.Request(url: urlString)

        let cacheStream = Internals.AsyncStream<Internals.DataBuffer>()

        // When
        let task = try await session.execute(
            client: client,
            request: request,
            url: urlString,
            readingMode: .length(2_048),
            uploadingBytes: .zero,
            decompression: .disabled,
            cache: { _ in cacheStream },
            logger: nil
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

        for try await step in task.response {
            guard case .download(let downloadStep) = step else { continue }
            for try await chunk in downloadStep.bytes {
                downloadedChunks.append(chunk)
            }
        }

        // Then: the cache stream must close on its own once the download finishes, or
        // `cachedChunks` above would hang forever.
        let assembledDownload = downloadedChunks.reduce(Data(), +)
        let assembledCache = try await cachedChunks.reduce(Data(), +)

        #expect(assembledCache == assembledDownload)
        #expect(!assembledCache.isEmpty)
    }

    /// Regression guard for the gate `Internals.CacheControl`'s manual-decompression fix added:
    /// caching a response this package still has to decode itself would persist the still-
    /// compressed wire bytes under a cached head that (on replay, which never re-runs
    /// decompression) claims they're already decoded. So whenever
    /// `Internals.ManualDecompressionDispatch.requiresManualDecoding(for:)` answers `true` for a
    /// response, the cache tee must never attach at all -- not attach and receive nothing, which
    /// would still leave a `dataCache.trackWrite` task, in the real `Internals.CacheControl`
    /// pipeline this test bypasses, allocating a cache entry for a response that will never
    /// finish writing to it.
    ///
    /// Verified by temporarily dropping `decompressionDispatch` from `runExchange`'s parameter
    /// list and its `requiresManualDecoding` guard the same way the `.urlSession` rewrite
    /// accidentally did: this test then fails, since `cache` is invoked and `cacheStream` receives
    /// the (still identity-"encoded") body instead of closing empty.
    @Test
    func whenCacheProvidedAndManualDecompressionRequired_skipsTheCacheTee() async throws {
        // Given
        let localServer = try await LocalServer(.standard)
        let uri = "/" + UUID().uuidString
        let output = String(repeating: "the quick brown fox jumps over the lazy dog ", count: 500)

        localServer.insert(
            try LocalServer.ResponseConfiguration(
                headers: ["Content-Encoding": IdentityTestAlgorithm.contentEncoding],
                jsonObject: output
            ),
            at: uri
        )
        defer { localServer.cleanup(at: uri) }

        let session = makeSession(decompression: .enabled(algorithms: [IdentityTestAlgorithm()], limit: .none))
        let client = try await session.client()
        let urlString = "https://\(localServer.baseURL)\(uri)"
        let request = try HTTPClient.Request(url: urlString)

        var cacheInvoked = false
        let cacheStream = Internals.AsyncStream<Internals.DataBuffer>()

        // When
        let task = try await session.execute(
            client: client,
            request: request,
            url: urlString,
            readingMode: .length(2_048),
            uploadingBytes: .zero,
            decompression: .enabled(algorithms: [IdentityTestAlgorithm()], limit: .none),
            cache: { _ in
                cacheInvoked = true
                return cacheStream
            },
            logger: nil
        )

        var downloadedChunks: [Data] = []

        for try await step in task.response {
            guard case .download(let downloadStep) = step else { continue }
            for try await chunk in downloadStep.bytes {
                downloadedChunks.append(chunk)
            }
        }

        // Then: the download itself still succeeds (manual decoding runs on the live path
        // regardless of caching), but nothing was ever handed to the cache.
        let decoded = try HTTPResult<String>(downloadedChunks.reduce(Data(), +))
        #expect(decoded.response == output)
        #expect(!cacheInvoked)
    }
}

#endif
