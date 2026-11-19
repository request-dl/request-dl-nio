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

/// Work the caller of a request ends up waiting for, directly or through what it reads, runs at
/// the priority of that request. A fixed low priority is a priority inversion: under load the
/// cooperative pool leaves it for last, while the request that depends on it is not.
struct CachePriorityTests {

    private final class Box<Value: Sendable>: @unchecked Sendable {

        private let lock = SwiftAsyncStream.Lock()
        private var value: Value

        init(_ value: Value) {
            self.value = value
        }

        func get() -> Value {
            lock.withLock { value }
        }

        func set(_ newValue: Value) {
            lock.withLock { value = newValue }
        }
    }

    /// Never asked to do anything: nothing is stored for the request, so the cache is not
    /// revalidated and no request goes out.
    private struct UnusedClient: RequestExecutingClient {

        func execute(
            configuration: RequestConfiguration,
            decompression: Internals.Decompression,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.Chunk>?)?,
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

    // MARK: - The replay of a cached body

    @Test
    func startReplay_fromAHighPriorityTask_runsTheReplayAtItsPriority() async throws {
        try await withTemporaryFileURL("entry.bin") { fileURL in
            // Given: a body that stops being readable after its first piece, which is the one
            // way a replay runs code of its caller's (`onUnreadable`) from inside its own task.
            try Data(repeating: 0x5A, count: Internals.CacheControl.replayPieceSize * 3).write(to: fileURL)
            var body: Internals.AnyBuffer = await Internals.FileBuffer(fileURL)
            let first = try #require(await Internals.CacheControl.readPiece(of: &body))

            // Emptied in place, not removed: the file is open by now, and a removed one stays
            // readable through the descriptor it was opened with.
            try Data().write(to: fileURL)

            let window = Internals.FlowControlWindow()
            let download = await Internals.DownloadBuffer(readingMode: .length(1_024), flowControl: window)
            let observed = Box<_Concurrency.TaskPriority?>(nil)
            let body_ = body

            // When
            let replay = await _Concurrency.Task(priority: .high) {
                Internals.CacheControl.startReplay(
                    body_,
                    startingWith: first,
                    into: download,
                    window: window
                ) {
                    observed.set(_Concurrency.Task.currentPriority)
                }
            }.value

            await replay.value

            // Then: it did run, and at the priority of the task that started it.
            #expect(observed.get() == .high)
        }
    }

    // MARK: - The write of a response

    /// The head of a response arrives on whatever delivers it, an event loop, which is not the
    /// request's task and has no priority of its own to speak of. The write still belongs to the
    /// request.
    @Test
    func cache_whenTheHeadArrivesOutsideTheRequest_writesAtTheRequestsPriority() async throws {
        // Given
        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com/" + UUID().uuidString
        configuration.cachePolicy = .memory
        configuration.cacheStrategy = .returnCachedDataElseLoad

        let url = configuration.url
        let configuration_ = configuration
        let dataCache = DataCache(memoryCapacity: 1_024 * 1_024, diskCapacity: .zero, suiteName: UUID().uuidString)
        let observed = Box<_Concurrency.TaskPriority?>(nil)

        // When: the request is made by a high priority task...
        let onHead = await _Concurrency.Task(priority: .high) {
            () -> (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.Chunk>?)? in
            var control = Internals.CacheControl(
                requestConfiguration: configuration_,
                dataCache: dataCache,
                logger: nil
            )

            control.beforeWriting = {
                observed.set(_Concurrency.Task.currentPriority)
            }

            guard case .cache(let onHead?, _) = await control(UnusedClient()) else {
                return nil
            }

            return onHead
        }.value

        // ...and its head arrives from a task of the lowest one.
        let stream = await _Concurrency.Task.detached(priority: .background) {
            onHead?(
                Internals.ResponseHead(
                    url: url,
                    status: .init(code: 200, reason: "OK"),
                    version: .init(minor: 1, major: 1),
                    headers: [.init(name: "Content-Length", value: "0")],
                    isKeepAlive: true
                )
            )
        }.value

        stream?.close()
        await dataCache.waitUntilIdle()

        // Then
        #expect(stream != nil)
        #expect(observed.get() == .high)
    }
}
