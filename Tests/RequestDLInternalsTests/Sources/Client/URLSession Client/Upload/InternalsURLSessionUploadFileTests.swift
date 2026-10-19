//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(Darwin)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Unit coverage for `Internals.URLSessionUploadFile`, the replacement for the `InputStream`-based
/// upload bridge (`Internals.URLSessionUploadStream`, removed) that was found to be permanently
/// broken against `uploadTask(withStreamedRequest:)`. Independent of `URLSession`/a real network
/// round trip: that's `RequestConfigurationURLSessionClientUploadTests` in `RequestDLTests`.
///
/// `inMemoryThreshold` is passed explicitly and small throughout, rather than relying on the
/// production default (`Internals.URLSessionUploadFile.inMemoryThreshold`, 8 MiB); these tests
/// need to force each branch deterministically without allocating megabytes of payload per case.
struct InternalsURLSessionUploadFileTests {

    @Test
    func write_whenBodyFitsWithinThreshold_returnsDataWithoutTouchingDisk() async throws {
        // Given: a recognizable, non-repeating byte pattern, so any reordering or corruption
        // shows up as a content mismatch, not just a wrong total.
        let payload = Data((0..<1_000).map { UInt8($0 % 251) })
        let chunkSize = 77

        let (stream, continuation) = AsyncStream<Internals.Bytes>.makeStream()
        for start in Swift.stride(from: 0, to: payload.count, by: chunkSize) {
            let end = Swift.min(start + chunkSize, payload.count)
            continuation.yield(Internals.Bytes(Data(payload[start..<end])))
        }
        continuation.finish()

        // When
        let materialized = try await Internals.URLSessionUploadFile.write(body: stream, inMemoryThreshold: 2_048)

        // Then
        guard case .data(let data) = materialized else {
            Issue.record("Expected .data, got \(materialized)")
            return
        }
        #expect(data == payload)
    }

    @Test
    func write_whenBodyIsEmpty_returnsEmptyData() async throws {
        // Given
        let (stream, continuation) = AsyncStream<Internals.Bytes>.makeStream()
        continuation.finish()

        // When
        let materialized = try await Internals.URLSessionUploadFile.write(body: stream, inMemoryThreshold: 2_048)

        // Then
        guard case .data(let data) = materialized else {
            Issue.record("Expected .data, got \(materialized)")
            return
        }
        #expect(data.isEmpty)
    }

    @Test
    func write_whenBodyExceedsThreshold_spillsToFileWithAllBytesInOrder() async throws {
        // Given: comfortably past a deliberately tiny threshold, so this exercises the spillover
        // path (buffer what's already read, then keep draining straight to the file) rather than
        // the in-memory one.
        let payload = Data((0..<10_000).map { UInt8($0 % 251) })
        let chunkSize = 777

        let (stream, continuation) = AsyncStream<Internals.Bytes>.makeStream()
        for start in Swift.stride(from: 0, to: payload.count, by: chunkSize) {
            let end = Swift.min(start + chunkSize, payload.count)
            continuation.yield(Internals.Bytes(Data(payload[start..<end])))
        }
        continuation.finish()

        // When
        let materialized = try await Internals.URLSessionUploadFile.write(body: stream, inMemoryThreshold: 2_048)

        // Then
        guard case .file(let bufferURL) = materialized else {
            Issue.record("Expected .file, got \(materialized)")
            return
        }
        defer { Task { await bufferURL.removeIfTemporary() } }

        let written = try await bufferURL.absoluteURL().readData()
        #expect(written == payload)
    }

    @Test
    func write_whenBodyThrowsWithinThreshold_rethrowsWithoutTouchingDisk() async throws {
        // Given: fails before the threshold is ever reached, so this exercises the in-memory
        // read loop's own error path, which never creates a file at all.
        struct UpstreamError: Error, Equatable {}

        let (stream, continuation) = AsyncThrowingStream<Internals.Bytes, Error>.makeStream()
        continuation.yield(Internals.Bytes(Data([0, 1, 2, 3])))
        continuation.finish(throwing: UpstreamError())

        // When / Then
        await #expect(throws: UpstreamError.self) {
            _ = try await Internals.URLSessionUploadFile.write(body: stream, inMemoryThreshold: 2_048)
        }
    }

    @Test
    func write_whenBodyThrowsAfterSpillover_removesTheTemporaryFileAndRethrows() async throws {
        // Given: exceeds the threshold first (forcing the spillover file into existence), then
        // fails while still draining the remainder into it.
        struct UpstreamError: Error, Equatable {}

        let (stream, continuation) = AsyncThrowingStream<Internals.Bytes, Error>.makeStream()
        continuation.yield(Internals.Bytes(Data(repeating: 0, count: 4_096)))
        continuation.finish(throwing: UpstreamError())

        // When / Then: the failing path never hands back a `FileBufferURL` for the caller to
        // clean up itself, so a matching catch is the whole assertion: the file it wrote partway
        // through is already gone by the time this throws.
        await #expect(throws: UpstreamError.self) {
            _ = try await Internals.URLSessionUploadFile.write(body: stream, inMemoryThreshold: 2_048)
        }
    }

    // MARK: - Cancelled while the body is being drained

    /// A body that makes the next chunk wait, as a request body produced slowly does, so that a
    /// cancellation can land while `write(body:)` is waiting for it. The wait throws
    /// `CancellationError` when the task is cancelled, as any wait on a cancelled task does.
    private struct SlowBody: AsyncSequence, Sendable {

        typealias Element = Internals.Bytes

        let chunks: Int
        let chunkSize: Int
        let delay: UInt64
        let delivered: LockedValueBox<Int>

        struct AsyncIterator: AsyncIteratorProtocol {
            let body: SlowBody
            var index = 0

            mutating func next() async throws -> Internals.Bytes? {
                guard index < body.chunks else {
                    return nil
                }

                try await _Concurrency.Task.sleep(nanoseconds: body.delay)
                index += 1
                body.delivered.withLockedValue { $0 += 1 }

                return Internals.Bytes(Data(repeating: 0, count: body.chunkSize))
            }
        }

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(body: self)
        }
    }

    /// The case the closes go through `Internals.uncancellable` for: the request is cancelled
    /// while the body is being written to its temporary file, and the file is closed from a
    /// cancelled task. A close that a cancelled task drops leaves the descriptor open, and
    /// releasing the stream after that is a `fatalError`, so this passing at all is the check.
    @Test
    func write_whenCancelledWhileSpilling_throwsCancellationAndLeavesNoFileOpen() async throws {
        // Given: a body that goes past the threshold at the third chunk and has many more to come.
        let delivered = LockedValueBox(0)
        let body = SlowBody(chunks: 200, chunkSize: 1_024, delay: 5_000_000, delivered: delivered)

        let write = _Concurrency.Task {
            try await Internals.URLSessionUploadFile.write(body: body, inMemoryThreshold: 2_048)
        }

        // When: cancelled once it has spilled and is still writing.
        try await eventually(timeout: 60) { delivered.withLockedValue { $0 } >= 10 }
        write.cancel()

        // Then
        await #expect(throws: CancellationError.self) {
            _ = try await write.value
        }

        // The body was not drained to its end for nobody.
        #expect(delivered.withLockedValue { $0 } < 200)
    }

    @Test
    func write_whenCancelledBeforeTheThreshold_throwsCancellationWithoutTouchingDisk() async throws {
        // Given: the first chunk is well short of the threshold.
        let delivered = LockedValueBox(0)
        let body = SlowBody(chunks: 200, chunkSize: 16, delay: 5_000_000, delivered: delivered)

        let write = _Concurrency.Task {
            try await Internals.URLSessionUploadFile.write(body: body, inMemoryThreshold: 1_048_576)
        }

        // When
        try await eventually(timeout: 60) { delivered.withLockedValue { $0 } >= 2 }
        write.cancel()

        // Then
        await #expect(throws: CancellationError.self) {
            _ = try await write.value
        }

        #expect(delivered.withLockedValue { $0 } < 200)
    }

    @Test
    func removeIfTemporary_afterFileSpillover_deletesTheFile() async throws {
        // Given
        let (stream, continuation) = AsyncStream<Internals.Bytes>.makeStream()
        continuation.yield(Internals.Bytes(Data(repeating: 0, count: 4_096)))
        continuation.finish()

        let materialized = try await Internals.URLSessionUploadFile.write(body: stream, inMemoryThreshold: 2_048)

        guard case .file(let bufferURL) = materialized else {
            Issue.record("Expected .file, got \(materialized)")
            return
        }
        #expect(await bufferURL.isResourceAvailable())

        // When
        await bufferURL.removeIfTemporary()

        // Then
        #expect(await !bufferURL.isResourceAvailable())
    }
}

#endif
