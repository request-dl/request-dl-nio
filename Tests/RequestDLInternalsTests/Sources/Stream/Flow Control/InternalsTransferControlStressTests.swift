//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

/// Races suspend/resume against transfers in flight: many transfers at once, in both directions,
/// each toggled on its own schedule, some of them losing their connection along the way. Whatever
/// the interleaving, every body has to arrive intact and complete, and nothing may hang.
///
/// Aimed at the handful of places where a suspension meets a producer's own bookkeeping: the `.nio`
/// paused body part (completed by the window *or* by a hand-over to a continuation), the
/// `.urlSession` upload pump's gate registration, and a reconnection waiting on the gate.
@Suite(
    .serialized,
    .concurrent(watchdogAffectedPlatformConcurrencyLimit),
    .nonFatalWatchdog,
    .toleratingSimulatorFlake(
        "It moves many transfers at once and holds them still, which a simulator runner starved of CPU for minutes (this suite has taken over 260s there, and a job has been lost to it) can't promise; the other platforms are what catch a regression"
    )
)
struct InternalsTransferControlStressTests {

    @Test(arguments: TransferExecutor.allCases)
    func rapidToggling_underConcurrentTransfers_deliversEveryBodyIntact(_ executor: TransferExecutor) async throws {
        let downloadSize = 12 * 1_048_576
        let uploadSize = 6 * 1_048_576
        let transfers = 6

        try await withTransferServer(.init(length: downloadSize)) { server in
            // Every other download loses its connection once, somewhere in the middle.
            server.dropPlan = (0..<transfers).map { $0.isMultiple(of: 2) ? 3_000_000 + $0 * 100_003 : nil }

            let harness = TransferHarness(executor)

            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<transfers {
                    group.addTask {
                        let control = Internals.TransferControl(
                            resumption: .init(maximumAttemptsWithoutProgress: 3, delay: 0)
                        )
                        let download = try await harness.download(from: server, transferControl: control)
                        let reader = BackgroundReader(download.step.bytes)

                        let toggler = Task {
                            var suspended = false

                            while reader.outcome == nil, !Task.isCancelled {
                                suspended.toggle()
                                suspended ? control.suspend() : control.resume()
                                try? await Task.sleep(nanoseconds: UInt64(5_000_000 + index * 3_000_000))
                            }

                            control.resume()
                        }

                        let outcome = try await reader.end(within: 120)
                        toggler.cancel()
                        _ = await toggler.value

                        #expect(outcome == .finished, "download \(index): \(String(describing: reader.error))")
                        #expect(reader.verifier.isIntact, "download \(index)")
                        #expect(reader.position == downloadSize, "download \(index)")

                        withExtendedLifetime(download) {}
                    }

                    group.addTask {
                        let control = Internals.TransferControl()
                        let (task, owner) = try await harness.upload(
                            to: server,
                            size: uploadSize,
                            path: "/upload-\(index)",
                            transferControl: control
                        )

                        let toggler = Task {
                            var suspended = false

                            while !Task.isCancelled {
                                suspended.toggle()
                                suspended ? control.suspend() : control.resume()
                                try? await Task.sleep(nanoseconds: UInt64(4_000_000 + index * 2_000_000))
                            }

                            control.resume()
                        }

                        let status = try await completing(within: 120) { () -> UInt in
                            var status: UInt = 0

                            for try await step in task.response {
                                if case .download(let download) = step {
                                    status = download.head.status.code
                                    for try await _ in download.bytes {}
                                }
                            }

                            return status
                        }

                        toggler.cancel()
                        _ = await toggler.value

                        #expect(status == 200, "upload \(index)")
                        withExtendedLifetime(owner) {}
                    }
                }

                try await group.waitForAll()
            }

            // Every upload arrived whole and exactly once.
            let requests = server.requests
            let uploads = requests.filter { $0.method == "PUT" }
            let wholeUploads = uploads.filter { $0.isBodyIntact && $0.isBodyComplete && $0.bodyLength == uploadSize }
            #expect(uploads.count == transfers)
            #expect(wholeUploads.count == transfers)

            // Every dropped download was continued, and only those.
            let continuations = requests.filter { $0.header("Range") != nil }
            let partialContents = continuations.filter { $0.status == 206 }
            #expect(continuations.count == transfers / 2)
            #expect(partialContents.count == continuations.count)
        }
    }
}
