//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// `.continuingDownload(from:)` through the public API, against a real ``TransferServer`` on each
/// executor: asking for the rest of a download from a saved point, and refusing anything that isn't
/// exactly that.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct ContinuingDownloadFromPointRequestTaskTests {

    private static let length = 8 * 1_048_576

    private typealias Executor = TransferTestExecutor

    // MARK: - Helpers

    private static func download(from server: TransferServer, executor: Executor) -> DownloadTask<some Property> {
        DownloadTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path("/resource")
            executor.session
        }
    }

    /// A point the way a first launch would have kept it: from the head of the original response.
    private static func point(
        from server: TransferServer,
        executor: Executor,
        offset: Int
    ) async throws -> DownloadResumptionPoint {
        let original = try await download(from: server, executor: executor).result()
        return try #require(DownloadResumptionPoint(head: original.head, offset: Int64(offset)))
    }

    /// A point that needs no server at all, for the requests that must not reach one.
    private static func offlinePoint(offset: Int64) throws -> DownloadResumptionPoint {
        try #require(
            DownloadResumptionPoint(
                head: ResponseHead(
                    url: nil,
                    status: .init(code: 200, reason: "OK"),
                    version: .init(minor: 1, major: 1),
                    headers: HTTPHeaders([("ETag", "\"v1\""), ("Content-Length", "1000")]),
                    isKeepAlive: true
                ),
                offset: offset
            )
        )
    }

    /// Reads what is left of a download, checking every byte against the position-dependent pattern
    /// ``TransferServer`` serves, from `offset` on: a repeated, skipped or mixed-up range would show
    /// up as a byte in the wrong place.
    private static func read(
        _ result: TaskResult<AsyncBytes>,
        from offset: Int,
        seed: Int = 0
    ) async throws -> (count: Int, isIntact: Bool) {
        var count = 0
        var isIntact = true

        for try await chunk in result.payload {
            for (index, byte) in chunk.enumerated()
            where byte != TransferServer.byte(at: offset + count + index, seed: seed) {
                isIntact = false
            }

            count += chunk.count
        }

        return (count, isIntact)
    }

    /// The error a task fails with, or `nil` if it didn't fail with one.
    private static func resumptionError(
        of task: some RequestTask<TaskResult<AsyncBytes>>
    ) async -> DownloadResumptionError? {
        do {
            _ = try await task.result()
            return nil
        } catch {
            return error as? DownloadResumptionError
        }
    }

    // MARK: - The rest of the download

    @Test(arguments: Executor.allCases)
    private func resumesFromTheOffset_andDeliversExactlyTheRest(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            let offset = 3_000_000
            let point = try await Self.point(from: server, executor: executor, offset: offset)

            // When
            let result = try await Self.download(from: server, executor: executor)
                .continuingDownload(from: point)
                .result()

            // Then: a `206` carrying only what comes after the offset, byte for byte.
            #expect(result.head.status.code == 206)

            let (count, isIntact) = try await Self.read(result, from: offset)
            #expect(count == Self.length - offset)
            #expect(isIntact)

            // And it asked the way a continuation has to: from the offset, only if unchanged.
            try await eventually(timeout: 30) { server.requests.contains { $0.header("Range") != nil } }

            let request = try #require(server.requests.first { $0.header("Range") != nil })
            #expect(request.header("Range") == "bytes=\(offset)-")
            #expect(request.header("If-Range") == "\"v1\"")
        }
    }

    /// The case this exists for: what the first launch received and kept, the point it kept next to
    /// it, and a second launch that continues from there.
    @Test(arguments: Executor.allCases)
    private func aPointKeptAcrossALaunch_continuesTheDownloadIntact(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given: a first launch that got some of the body, and was closed.
            let first = try await Self.download(from: server, executor: executor).result()
            var received = 0
            var firstPartIsIntact = true

            for try await chunk in first.payload {
                for (index, byte) in chunk.enumerated()
                where byte != TransferServer.byte(at: received + index, seed: 0) {
                    firstPartIsIntact = false
                }

                received += chunk.count

                if received >= 700_000 {
                    break
                }
            }

            let stored = try JSONEncoder().encode(
                try #require(DownloadResumptionPoint(head: first.head, offset: Int64(received)))
            )

            // When: a second launch reads the point back, and asks for the rest.
            let point = try JSONDecoder().decode(DownloadResumptionPoint.self, from: stored)

            let rest = try await Self.download(from: server, executor: executor)
                .continuingDownload(from: point)
                .result()

            let (count, isIntact) = try await Self.read(rest, from: received)

            // Then: the two parts add up to the whole resource.
            #expect(firstPartIsIntact)
            #expect(isIntact)
            #expect(received + count == Self.length)
        }
    }

    @Test(arguments: Executor.allCases)
    private func aDataTask_getsTheRestToo(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            let offset = 5_000_000
            let point = try await Self.point(from: server, executor: executor, offset: offset)

            // When
            let data = try await DataTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Path("/resource")
                executor.session
            }
            .extractPayload()
            .continuingDownload(from: point)
            .result()

            // Then
            #expect(data.count == Self.length - offset)
            #expect(data.enumerated().allSatisfy { $0.element == TransferServer.byte(at: offset + $0.offset, seed: 0) })
        }
    }

    // MARK: - With reconnection

    /// A download continued from a saved point is the one most likely to be cut again, so a lost
    /// connection reconnects (when asked to) from everything received since the point, not from
    /// the point itself.
    @Test(arguments: Executor.allCases)
    private func withResumingDownloads_aLostConnectionContinuesFromWhereItGot(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given: a point, then a server that cuts the continuation a megabyte in.
            let offset = 2_000_000
            let point = try await Self.point(from: server, executor: executor, offset: offset)
            server.dropPlan = [1_000_000]

            // When
            let result = try await Self.download(from: server, executor: executor)
                .resumingDownloads(.enabled(delay: 0))
                .continuingDownload(from: point)
                .result()

            // Then: the rest of the resource, whole and in place, across the two connections.
            let (count, isIntact) = try await Self.read(result, from: offset)
            #expect(count == Self.length - offset)
            #expect(isIntact)

            // The first request asked from the point; the next one from further on, but never from
            // before it or from past what the cut connection carried.
            try await eventually(timeout: 30) { server.requests.filter { $0.header("Range") != nil }.count >= 2 }

            let starts = server.requests
                .compactMap { $0.header("Range") }
                .compactMap { Int($0.dropFirst("bytes=".count).dropLast()) }

            #expect(starts.first == offset)
            #expect(starts.dropFirst().allSatisfy { $0 > offset && $0 <= offset + 1_000_000 })
        }
    }

    @Test(arguments: Executor.allCases)
    private func withoutResumingDownloads_aLostConnectionStillFails(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            let point = try await Self.point(from: server, executor: executor, offset: 2_000_000)
            server.dropPlan = [1_000_000]

            // When
            let result = try await Self.download(from: server, executor: executor)
                .continuingDownload(from: point)
                .result()

            // Then: reconnecting is something asked for, not something a saved point implies.
            await #expect(throws: (any Error).self) {
                _ = try await Self.read(result, from: 2_000_000)
            }
        }
    }

    /// The error is the same public one whichever way the rest of a download was asked for: here by
    /// a reconnection that found the resource changed, not by a point.
    @Test(arguments: Executor.allCases)
    private func aResourceThatChangesWhileReconnecting_failsWithThePublicError(_ executor: Executor) async throws {
        let length = 64 * 1_048_576

        try await withTransferServer(.init(length: length)) { server in
            // Given: a download under way, whose connection is lost while it is suspended, and a
            // server that holds another version of the resource by the time it is resumed.
            let controller = RequestController()
            let result = try await Self.download(from: server, executor: executor)
                .resumingDownloads(.enabled(delay: 0))
                .controller(controller)
                .result()

            var iterator = result.payload.makeAsyncIterator()
            _ = try await iterator.next()

            controller.suspend()
            _ = try await server.settled { server.bodyBytesWritten }

            server.closeConnections()
            try await eventually(timeout: 30) { server.openConnections == 0 }
            server.resource = .init(length: length, seed: 7, validator: .entityTag("\"v2\""))

            // When
            controller.resume()

            // Then
            var failure: (any Error)?

            do {
                while try await iterator.next() != nil {}
            } catch {
                failure = error
            }

            #expect((failure as? DownloadResumptionError)?.reason == .representationChanged)
        }
    }

    // MARK: - What isn't the rest

    @Test(arguments: Executor.allCases)
    private func aResourceThatChanged_isRefused_andNothingOfItIsDelivered(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given: a point of one version, and the server now holding another.
            let point = try await Self.point(from: server, executor: executor, offset: 1_000_000)
            server.resource = .init(length: Self.length, seed: 7, validator: .entityTag("\"v2\""))

            // When
            let error = await Self.resumptionError(
                of: Self.download(from: server, executor: executor).continuingDownload(from: point)
            )

            // Then: `If-Range` no longer matched, so the server sent the whole new resource, which
            // can't be spliced, and the task failed before handing any of it on.
            #expect(error?.reason == .representationChanged)
        }
    }

    @Test(arguments: Executor.allCases)
    private func aServerWithoutRangeSupport_isRefused(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            let point = try await Self.point(from: server, executor: executor, offset: 1_000_000)
            server.resource = .init(length: Self.length, supportsRanges: false)

            // When
            let error = await Self.resumptionError(
                of: Self.download(from: server, executor: executor).continuingDownload(from: point)
            )

            // Then
            #expect(error?.reason == .representationChanged)
        }
    }

    @Test(arguments: Executor.allCases)
    private func aPointAtTheEnd_saysThereIsNothingLeft(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given: a point exactly at the end of the resource.
            let point = try await Self.point(from: server, executor: executor, offset: Self.length)
            #expect(point.isComplete)

            // When
            let error = await Self.resumptionError(
                of: Self.download(from: server, executor: executor).continuingDownload(from: point)
            )

            // Then: not a failure, and said apart from the ones that are.
            #expect(error?.reason == .alreadyComplete)
        }
    }

    @Test(arguments: Executor.allCases)
    private func aPointPastTheEnd_cantBeSatisfied(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given: the resource turned out shorter than the partial download.
            let point = try await Self.point(from: server, executor: executor, offset: Self.length + 4_096)

            // When
            let error = await Self.resumptionError(
                of: Self.download(from: server, executor: executor).continuingDownload(from: point)
            )

            // Then
            #expect(error?.reason == .unsatisfiableRange)
        }
    }

    // MARK: - Requests that can't be continued

    @Test(arguments: Executor.allCases)
    private func aRequestThatIsNotAGet_isRefused_withoutBeingSent(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // When
            let error = await Self.resumptionError(
                of: DownloadTask {
                    BaseURL(.http, host: "127.0.0.1:\(server.port)")
                    Path("/resource")
                    RequestMethod(.post)
                    executor.session
                }
                .continuingDownload(from: try Self.offlinePoint(offset: 100))
            )

            // Then
            #expect(error?.reason == .requestNotResumable)
            #expect(server.acceptedConnections == 0)
        }
    }

    @Test(arguments: Executor.allCases)
    private func aRequestWithARangeOfItsOwn_isRefused_withoutBeingSent(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // When
            let error = await Self.resumptionError(
                of: DownloadTask {
                    BaseURL(.http, host: "127.0.0.1:\(server.port)")
                    Path("/resource")
                    CustomHeader(name: "Range", value: "bytes=0-9")
                    executor.session
                }
                .continuingDownload(from: try Self.offlinePoint(offset: 100))
            )

            // Then
            #expect(error?.reason == .requestNotResumable)
            #expect(server.acceptedConnections == 0)
        }
    }
}
