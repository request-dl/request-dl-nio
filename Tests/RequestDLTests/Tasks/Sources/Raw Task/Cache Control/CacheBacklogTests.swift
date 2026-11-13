//
// See LICENSE for this package's licensing information.
//

import Logging
@_spi(Testing) import RequestDLInternals
import SwiftAsyncStream
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
#endif

/// The response is stored while it downloads, through a stream the download feeds and the cache
/// writer reads. The network is never held back for that writer, so the stream's backlog has a
/// bound (`Internals.DownloadBuffer.cacheBacklogLimit`): a writer that falls further behind than
/// that has its response left out of the cache, and the request goes on as if nothing happened.
///
/// These go through `Internals.CacheControl` itself, from the decision to cache a response to the
/// entry that is, or is not, in the `DataCache`, with the real writer. The writer is held back with
/// `Internals.CacheControl.beforeWriting` where the test needs it behind, instead of hoping that a
/// busy `DataCache` makes it so.
struct CacheBacklogTests {

    private let megabyte = 1_024 * 1_024

    private final class Records: @unchecked Sendable {

        var all: [TestLogHandler.LogRecord] {
            lock.withLock { _all }
        }

        private let lock = SwiftAsyncStream.Lock()
        private var _all: [TestLogHandler.LogRecord] = []

        func append(_ record: TestLogHandler.LogRecord) {
            lock.withLock { _all.append(record) }
        }
    }

    /// Never asked to do anything: nothing is stored for the request, so the cache is not
    /// revalidated and no request goes out.
    private struct UnusedClient: RequestExecutingClient {

        func execute(
            configuration: RequestConfiguration,
            decompression: Internals.Decompression,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: Internals.TaskLogger?,
            transferControl: Internals.TransferControl?
        ) async throws -> SessionTask {
            fatalError("The cache was empty, and nothing here sends a request")
        }

        func revalidationHead(
            configuration: RequestConfiguration,
            logger: Internals.TaskLogger?,
            metrics: Internals.RequestMetricsCollector?
        ) async throws -> Internals.ResponseHead {
            fatalError("The cache was empty, and nothing here sends a request")
        }
    }

    private func head(url: String, length: Int) -> Internals.ResponseHead {
        Internals.ResponseHead(
            url: url,
            status: .init(code: 200, reason: "OK"),
            version: .init(minor: 1, major: 1),
            headers: [.init(name: "Content-Length", value: String(length))],
            isKeepAlive: true
        )
    }

    /// What a client does with a response that is being downloaded: the body is fed to a download
    /// buffer, whose copy for the cache goes to the writer `Internals.CacheControl` started, and the
    /// caller reads the other.
    ///
    /// - Returns: How much of the body the caller received, and whether it was the one that was sent.
    private func download(
        _ length: Int,
        into dataCache: DataCache,
        holdingTheWriterUntil gate: AsyncSignal?,
        records: Records
    ) async throws -> (received: Int, intact: Bool, key: String) {
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com/" + UUID().uuidString
        configuration.cachePolicy = .memory
        configuration.cacheStrategy = .returnCachedDataElseLoad

        let key = configuration.url

        return try await Logger.withTesting(
            level: .trace,
            recorded: { records.append($0) },
            perform: { logger in
                var control = Internals.CacheControl(
                    requestConfiguration: configuration,
                    dataCache: dataCache,
                    logger: Internals.TaskLogger(baseURL: key, pathComponents: [], logger: logger)
                )

                if let gate {
                    control.beforeWriting = { try? await gate.wait() }
                }

                guard case .cache(let onHead?, _) = await control(UnusedClient()) else {
                    Issue.record("A response to a plain GET was not offered to the cache")
                    return (0, false, key)
                }

                let cacheStream = try #require(onHead(head(url: key, length: length)))
                let download = await Internals.DownloadBuffer(readingMode: .length(64 * 1_024))
                download.cacheStream(cacheStream)

                // The caller, reading as the body arrives.
                let reader = _Concurrency.Task { () -> (Int, Bool) in
                    var received = 0
                    var intact = true

                    for try await chunk in Internals.AsyncBytes(logger: nil, totalSize: length, stream: download.stream)
                    {
                        intact = intact && chunk.allSatisfy { $0 == 0x5A }
                        received += chunk.count
                    }

                    return (received, intact)
                }

                // The network, a megabyte at a time and with nothing to slow it down.
                var sent = 0

                while sent < length {
                    let part = min(megabyte, length - sent)
                    await download.append(Internals.DataBuffer(Data(repeating: 0x5A, count: part)))
                    sent += part
                }

                download.close()

                let (received, intact) = try await reader.value

                // Only now does the writer start, as far behind as it is going to be.
                gate?.signal()
                await dataCache.waitUntilIdle()

                return (received, intact, key)
            }
        )
    }

    private func makeCache() -> DataCache {
        DataCache(memoryCapacity: Int64(64 * megabyte), diskCapacity: .zero, suiteName: UUID().uuidString)
    }

    @Test
    func cache_whenTheWriterFallsMoreThanTheBacklogBehind_theCallerGetsTheWholeBodyAndNothingIsStored() async throws {
        // Given: a body a few megabytes past the bound, a writer that has not read a byte of it,
        // and room in the cache for all of it.
        let length = Internals.DownloadBuffer.cacheBacklogLimit + 4 * megabyte
        let dataCache = makeCache()
        let gate = AsyncSignal()
        let records = Records()

        // When
        let (received, intact, key) = try await download(
            length,
            into: dataCache,
            holdingTheWriterUntil: gate,
            records: records
        )

        // Then: the caller was not affected.
        #expect(received == length)
        #expect(intact)

        // And the response was left out of the cache, not stored as far as it got.
        #expect(await dataCache.getCachedData(forKey: key, policy: .all) == nil)

        // And it was said so.
        let warning = records.all.first { $0.level == .warning && "\($0.message)".contains("will not be cached") }
        #expect(warning != nil)
    }

    @Test
    func cache_whenTheWriterIsBehindButWithinTheBacklog_theResponseIsStoredWhole() async throws {
        // Given: the same writer, held back the same way, for a body that fits what is allowed to
        // wait for it.
        let length = Internals.DownloadBuffer.cacheBacklogLimit / 4
        let dataCache = makeCache()
        let gate = AsyncSignal()
        let records = Records()

        // When
        let (received, intact, key) = try await download(
            length,
            into: dataCache,
            holdingTheWriterUntil: gate,
            records: records
        )

        // Then
        #expect(received == length)
        #expect(intact)

        let cached = try #require(await dataCache.getCachedData(forKey: key, policy: .all))
        #expect(cached.buffer.readableBytes == length)
        #expect(records.all.allSatisfy { $0.level != .warning })
    }
}
