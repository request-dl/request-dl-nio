//
// See LICENSE for this package's licensing information.
//

import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// End-to-end coverage of `.resumingDownloads(_:)` through the public API, against a real
/// ``TransferServer`` that cuts connections mid-body, on each executor.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct ResumingDownloadsRequestTaskTests {

    private static let length = 8 * 1_048_576

    private static let cutAt = 1_000_000

    private typealias Executor = TransferTestExecutor

    private static func download(
        from server: TransferServer,
        executor: Executor
    ) -> DownloadTask<some Property> {
        DownloadTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path("/resource")
            executor.session
        }
    }

    /// Reads a download to its end, checking every byte against the position-dependent pattern
    /// ``TransferServer`` serves: a splice of two versions, or a repeated or skipped range, would
    /// show up as a byte in the wrong place.
    private static func read(
        _ task: some RequestTask<TaskResult<AsyncBytes>>,
        seed: Int = 0
    ) async throws -> (count: Int, isIntact: Bool) {
        var count = 0
        var isIntact = true

        for try await chunk in try await task.result().payload {
            for (offset, byte) in chunk.enumerated() where byte != TransferServer.byte(at: count + offset, seed: seed) {
                isIntact = false
            }

            count += chunk.count
        }

        return (count, isIntact)
    }

    // MARK: - Tests

    /// The default is unchanged: a lost connection fails the download.
    @Test(arguments: Executor.allCases)
    private func withoutAPolicy_aLostConnectionFailsTheDownload(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            server.dropPlan = [Self.cutAt]

            // When / Then
            await #expect(throws: (any Error).self) {
                _ = try await Self.read(Self.download(from: server, executor: executor))
            }

            // Long enough for a reconnection that shouldn't have happened to show up.
            try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            #expect(server.requests.count == 1)
        }
    }

    @Test(arguments: Executor.allCases)
    private func withAPolicy_aLostConnectionContinuesWhereItStopped(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            server.dropPlan = [Self.cutAt]

            // When
            let (count, isIntact) = try await Self.read(
                Self.download(from: server, executor: executor)
                    .resumingDownloads(.enabled(delay: 0))
            )

            // Then
            #expect(count == Self.length)
            #expect(isIntact)
            #expect(server.requests.count == 2)
            #expect(server.requests.last?.header("If-Range") == "\"v1\"")
            #expect(server.requests.last?.header("Range")?.hasPrefix("bytes=") == true)
        }
    }

    /// A body accumulated in memory continues the same way: nothing extra is stored.
    @Test(arguments: Executor.allCases)
    private func dataTask_continuesToo(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            server.dropPlan = [Self.cutAt]

            // When
            let data = try await DataTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Path("/resource")
                executor.session
            }
            .extractPayload()
            .resumingDownloads(.enabled(delay: 0))
            .result()

            // Then
            #expect(data.count == Self.length)
            #expect(data.enumerated().allSatisfy { $0.element == TransferServer.byte(at: $0.offset, seed: 0) })
            #expect(server.requests.count == 2)
        }
    }

    /// Only a strong validator is safe to splice against; anything else fails as it always did,
    /// and no continuation is even attempted.
    @Test(arguments: Executor.allCases)
    private func withoutAStrongValidator_theDownloadStillFails(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length, validator: .weakEntityTag("W/\"w\""))) { server in
            // Given
            server.dropPlan = [Self.cutAt]

            // When / Then
            await #expect(throws: (any Error).self) {
                _ = try await Self.read(
                    Self.download(from: server, executor: executor)
                        .resumingDownloads(.enabled(delay: 0))
                )
            }

            // Long enough for a reconnection that shouldn't have happened to show up.
            try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            #expect(server.requests.count == 1)
        }
    }

    /// The modifier closest to the task wins, so an outer `.disabled` doesn't undo an inner
    /// `.enabled`, and an outer `.enabled` doesn't turn on what an inner `.disabled` turned off.
    @Test(arguments: Executor.allCases)
    private func theModifierClosestToTheTaskWins(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            server.dropPlan = [Self.cutAt]

            // When
            let (count, isIntact) = try await Self.read(
                Self.download(from: server, executor: executor)
                    .resumingDownloads(.enabled(delay: 0))
                    .resumingDownloads(.disabled)
            )

            // Then
            #expect(count == Self.length)
            #expect(isIntact)
        }

        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            server.dropPlan = [Self.cutAt]

            // When / Then
            await #expect(throws: (any Error).self) {
                _ = try await Self.read(
                    Self.download(from: server, executor: executor)
                        .resumingDownloads(.disabled)
                        .resumingDownloads(.enabled(delay: 0))
                )
            }
        }
    }

    /// A controller and a policy on the same task work together: the download still reconnects,
    /// and still suspends.
    @Test(arguments: Executor.allCases)
    private func withAController_theDownloadStillContinues(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            server.dropPlan = [Self.cutAt]
            let controller = RequestController()

            // When
            let (count, isIntact) = try await Self.read(
                Self.download(from: server, executor: executor)
                    .resumingDownloads(.enabled(delay: 0))
                    .controller(controller)
            )

            // Then
            #expect(count == Self.length)
            #expect(isIntact)
            #expect(server.requests.count == 2)
        }
    }
}
