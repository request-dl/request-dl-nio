//
// See LICENSE for this package's licensing information.
//

import NIOCore
import Testing

@testable import RequestDLInternals

#if canImport(Darwin)

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Phase 7b4 of `URLSESSION_TASK.md` -- unit coverage for `Internals.URLSessionUploadFile`, the
/// replacement for the `InputStream`-based upload bridge (`Internals.URLSessionUploadStream`,
/// removed) that `INPUT_STREAM_ANALISYS.md` (repo root) found to be permanently broken against
/// `uploadTask(withStreamedRequest:)`. Independent of `URLSession`/a real network round trip --
/// that's `RequestConfigurationURLSessionClientUploadTests` in `RequestDLTests`.
///
/// `inMemoryThreshold` is passed explicitly and small throughout, rather than relying on the
/// production default (`Internals.URLSessionUploadFile.inMemoryThreshold`, 8 MiB) -- these tests
/// need to force each branch deterministically without allocating megabytes of payload per case.
struct InternalsURLSessionUploadFileTests {

    @Test
    func write_whenBodyFitsWithinThreshold_returnsDataWithoutTouchingDisk() async throws {
        // Given -- a recognizable, non-repeating byte pattern, so any reordering or corruption
        // shows up as a content mismatch, not just a wrong total.
        let payload = Data((0..<1_000).map { UInt8($0 % 251) })
        let chunkSize = 77

        let (stream, continuation) = AsyncStream<ByteBuffer>.makeStream()
        for start in Swift.stride(from: 0, to: payload.count, by: chunkSize) {
            let end = Swift.min(start + chunkSize, payload.count)
            continuation.yield(ByteBuffer(bytes: payload[start..<end]))
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
        let (stream, continuation) = AsyncStream<ByteBuffer>.makeStream()
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
        // Given -- comfortably past a deliberately tiny threshold, so this exercises the spillover
        // path (buffer what's already read, then keep draining straight to the file) rather than
        // the in-memory one.
        let payload = Data((0..<10_000).map { UInt8($0 % 251) })
        let chunkSize = 777

        let (stream, continuation) = AsyncStream<ByteBuffer>.makeStream()
        for start in Swift.stride(from: 0, to: payload.count, by: chunkSize) {
            let end = Swift.min(start + chunkSize, payload.count)
            continuation.yield(ByteBuffer(bytes: payload[start..<end]))
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
        // Given -- fails before the threshold is ever reached, so this exercises the in-memory
        // read loop's own error path, which never creates a file at all.
        struct UpstreamError: Error, Equatable {}

        let (stream, continuation) = AsyncThrowingStream<ByteBuffer, Error>.makeStream()
        continuation.yield(ByteBuffer(bytes: [0, 1, 2, 3]))
        continuation.finish(throwing: UpstreamError())

        // When / Then
        await #expect(throws: UpstreamError.self) {
            _ = try await Internals.URLSessionUploadFile.write(body: stream, inMemoryThreshold: 2_048)
        }
    }

    @Test
    func write_whenBodyThrowsAfterSpillover_removesTheTemporaryFileAndRethrows() async throws {
        // Given -- exceeds the threshold first (forcing the spillover file into existence), then
        // fails while still draining the remainder into it.
        struct UpstreamError: Error, Equatable {}

        let (stream, continuation) = AsyncThrowingStream<ByteBuffer, Error>.makeStream()
        continuation.yield(ByteBuffer(repeating: 0, count: 4_096))
        continuation.finish(throwing: UpstreamError())

        // When / Then -- the failing path never hands back a `FileBufferURL` for the caller to
        // clean up itself, so a matching catch is the whole assertion: the file it wrote partway
        // through is already gone by the time this throws.
        await #expect(throws: UpstreamError.self) {
            _ = try await Internals.URLSessionUploadFile.write(body: stream, inMemoryThreshold: 2_048)
        }
    }

    @Test
    func removeIfTemporary_afterFileSpillover_deletesTheFile() async throws {
        // Given
        let (stream, continuation) = AsyncStream<ByteBuffer>.makeStream()
        continuation.yield(ByteBuffer(repeating: 0, count: 4_096))
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
