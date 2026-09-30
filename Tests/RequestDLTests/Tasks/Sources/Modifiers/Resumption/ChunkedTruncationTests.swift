//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

/// A chunked response cut off exactly on a chunk boundary, without the terminating zero-length
/// chunk that says the body is complete.
///
/// The NIO executors see the connection close before the body was terminated and fail the
/// download. `URLSession` does not: for `bytes(for:)`, `data(for:)` and a delegate-based task alike,
/// CFNetwork reports a *successful, complete* response, with nothing else to tell the two apart
/// (`Transfer-Encoding` comes back as `Identity`, there is no `Content-Length`, and the task
/// metrics count wire bytes including chunk framing, which don't say whether the last chunk was
/// the last one). A cut in the middle of a chunk, by contrast, fails on every executor.
///
/// That leaves nothing RequestDL could check on `.urlSession`, and, since the body looks complete,
/// no reconnection either. These tests pin down the difference so it is a known, documented one.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct ChunkedTruncationTests {

    private static let length = 1_048_576

    /// A multiple of the server's 16 KiB chunk size: every chunk sent so far is whole.
    private static let cutOnAChunkBoundary = 8 * 16_384

    private static let cutInsideAChunk = 8 * 16_384 + 5_000

    private typealias Executor = TransferTestExecutor

    private static func download(from server: TransferServer, executor: Executor) async throws -> Int {
        let result = try await DownloadTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path("/resource")
            executor.session
        }
        .result()

        var count = 0

        for try await chunk in result.payload {
            count += chunk.count
        }

        return count
    }

    /// Cut inside a chunk: every executor can tell the body is truncated.
    @Test(arguments: Executor.allCases)
    private func cutInsideAChunk_failsOnEveryExecutor(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length, isChunked: true)) { server in
            server.dropPlan = [Self.cutInsideAChunk]

            await #expect(throws: (any Error).self) {
                _ = try await Self.download(from: server, executor: executor)
            }
        }
    }

    /// Cut on a chunk boundary: the NIO executors fail the download.
    @Test(arguments: Executor.allCases.filter { $0 != .urlSession })
    private func cutOnAChunkBoundary_failsOnTheNIOExecutors(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length, isChunked: true)) { server in
            server.dropPlan = [Self.cutOnAChunkBoundary]

            await #expect(throws: (any Error).self) {
                _ = try await Self.download(from: server, executor: executor)
            }
        }
    }

    #if canImport(Darwin)
    /// Cut on a chunk boundary, `.urlSession`: CFNetwork reports the truncated body as complete.
    /// A known, pre-existing platform behaviour; when it stops being one, this test says so.
    @Test
    private func cutOnAChunkBoundary_isNotDetectedByURLSession() async throws {
        try await withTransferServer(.init(length: Self.length, isChunked: true)) { server in
            server.dropPlan = [Self.cutOnAChunkBoundary]

            await withKnownIssue(
                "CFNetwork reports a chunked body cut on a chunk boundary as complete",
                isIntermittent: true
            ) {
                await #expect(throws: (any Error).self) {
                    _ = try await Self.download(from: server, executor: .urlSession)
                }
            }
        }
    }
    #endif
}
