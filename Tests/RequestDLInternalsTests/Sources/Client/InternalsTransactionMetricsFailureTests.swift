//
// See LICENSE for this package's licensing information.
//

import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

/// The error of a transaction, on every executor.
///
/// AsyncHTTPClient reports it per transaction. `URLSession` only reports an error for the task as a
/// whole, so `Internals.URLSessionClient` records it on the transaction that failed itself. These tests
/// run the same body on both, since parity is what is under test.
@Suite(.concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsTransactionMetricsFailureTests {

    private static let immediately = Internals.DownloadResumptionPolicy(maximumAttemptsWithoutProgress: 3, delay: 0)

    @Test(arguments: TransferExecutor.allCases)
    func connectionLostMidBody_recordsTheErrorOnTheTransaction(_ executor: TransferExecutor) async throws {
        try await withTransferServer(.init(length: 8 * 1_048_576)) { server in
            // Given
            server.dropPlan = [1_000_000]

            let download = try await TransferHarness(executor).download(from: server, transferControl: nil)
            let collector = try #require(download.task.metrics)

            // When
            var failed = false

            do {
                for try await _ in download.step.bytes {}
            } catch {
                failed = true
            }

            // Then: the metrics of the task arrive around the same time as its error, in either order.
            try await eventually {
                collector.transactions().last?.error != nil
            }

            #expect(failed)

            let transactions = collector.transactions()
            #expect(transactions.count == 1)
            #expect(transactions.first?.error != nil)

            withExtendedLifetime(download) {}
        }
    }

    @Test(arguments: TransferExecutor.allCases)
    func connectionLostMidBody_whenResumed_recordsTheErrorOfTheFailedExchangeOnly(
        _ executor: TransferExecutor
    ) async throws {
        try await withTransferServer(.init(length: 16 * 1_048_576)) { server in
            // Given
            server.dropPlan = [5_000_000]
            let control = Internals.TransferControl(resumption: Self.immediately)

            let download = try await TransferHarness(executor).download(from: server, transferControl: control)
            let collector = try #require(download.task.metrics)

            // When
            var total = 0

            for try await bytes in download.step.bytes {
                total += bytes.count
            }

            // Then: the exchange that was cut carries the error; the one that finished the body does not.
            try await eventually {
                collector.transactions().count == 2
            }

            #expect(total == 16 * 1_048_576)

            let transactions = collector.transactions()
            #expect(transactions.first?.error != nil)
            #expect(transactions.last?.error == nil)

            withExtendedLifetime(download) {}
        }
    }
}
