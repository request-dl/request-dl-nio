//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(NIOCore)
import AsyncHTTPClient
#endif

#if canImport(Darwin)
import Foundation
#elseif canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// End-to-end coverage for suspending and resuming a *download* in flight, and for reconnecting
/// one whose connection is lost, on both executors, by the same test bodies.
///
/// Every test observes the server: how many body bytes its kernel actually accepted, which
/// requests arrived with which headers. A suspension that only stopped the reader, not the
/// connection, would show up as that count running on to the end of the body; a continuation that
/// spliced two versions of the resource would show up as the reader's verifier catching a byte of
/// the wrong version.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsTransferControlDownloadTests {

    /// Far past the window, the client's socket buffers and CFNetwork's read-ahead combined, so a
    /// transfer that stalls well short of it can only have been stopped by the suspension.
    private static let largeBody = 128 * 1_048_576

    private static let immediately = Internals.DownloadResumptionPolicy(maximumAttemptsWithoutProgress: 3, delay: 0)

    // MARK: - In-flight suspension

    /// The core guarantee: suspending stops the *connection* -- the server can't get another byte
    /// out -- for as long as the suspension lasts, and resuming carries on over the same
    /// connection to an intact body.
    @Test(arguments: TransferExecutor.allCases)
    func suspendMidBody_holdsTheConnectionUntilResumed(_ executor: TransferExecutor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { server in
            // Given: an eager reader, so nothing but the suspension ever holds the transfer back.
            let control = Internals.TransferControl()
            let download = try await TransferHarness(executor).download(from: server, transferControl: control)
            let window = try #require(download.step.bytes.flowControlWindowForTesting)
            let reader = BackgroundReader(download.step.bytes)

            try await eventually(timeout: 30) { reader.position >= 4 * 1_048_576 }

            // When
            let writtenAtSuspension = server.bodyBytesWritten
            control.suspend()

            let stalledAt = try await server.settled { server.bodyBytesWritten }
            let readerStalledAt = try await reader.settledPosition()

            // Then: stalled far short of the body, and staying there.
            #expect(stalledAt < Self.largeBody / 2)

            try await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)

            #expect(server.bodyBytesWritten == stalledAt)
            #expect(reader.position == readerStalledAt)
            #expect(reader.outcome == nil)
            #expect(window.waitingCountForTesting == 1)
            #expect(!window.isReleasedForTesting)

            reportMeasurement("\(executor) download: bytes out after suspend()", stalledAt - writtenAtSuspension)
            reportMeasurement("\(executor) download: in flight past the reader", stalledAt - readerStalledAt)

            // When
            control.resume()

            // Then
            #expect(try await reader.end() == .finished)
            #expect(reader.verifier.isIntact)
            #expect(reader.position == Self.largeBody)
            #expect(server.acceptedConnections == 1)
            #expect(server.requests.count == 1)

            withExtendedLifetime(download) {}
        }
    }

    /// Suspended before the response even starts: the head still arrives (a suspension gates
    /// body bytes, not the exchange itself), then nothing more than the first step's worth until
    /// resumed.
    @Test(arguments: TransferExecutor.allCases)
    func suspendBeforeTheResponse_holdsTheBodyFromTheStart(_ executor: TransferExecutor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { server in
            // Given
            let control = Internals.TransferControl()
            control.suspend()

            // When
            let download = try await TransferHarness(executor).download(from: server, transferControl: control)
            let reader = BackgroundReader(download.step.bytes)

            let stalledAt = try await server.settled { server.bodyBytesWritten }
            _ = try await reader.settledPosition()

            // Then
            #expect(stalledAt < Self.largeBody / 2)
            reportMeasurement("\(executor) download suspended up front: bytes out", stalledAt)

            control.resume()

            #expect(try await reader.end() == .finished)
            #expect(reader.verifier.isIntact)
            #expect(reader.position == Self.largeBody)

            withExtendedLifetime(download) {}
        }
    }

    /// Cancelling a suspended request can't wait for a resume that will never come.
    @Test(arguments: TransferExecutor.allCases)
    func cancelWhileSuspended_failsTheReaderAndClosesTheConnection(_ executor: TransferExecutor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { server in
            // Given
            let control = Internals.TransferControl()
            let download = try await TransferHarness(executor).download(from: server, transferControl: control)
            let reader = BackgroundReader(download.step.bytes)

            try await eventually(timeout: 30) { reader.position > 0 }
            control.suspend()
            _ = try await server.settled { server.bodyBytesWritten }

            // When
            download.task.seed()

            // Then
            #expect(try await reader.end(within: 30).isFailure)
            try await eventually(timeout: 30) { server.openConnections == 0 }
            #expect(server.bodyBytesWritten < Self.largeBody)
        }
    }

    /// Dropping a suspended response, unread, cancels it like dropping any other response:
    /// the suspension must not keep the request (and its connection) alive.
    @Test(arguments: TransferExecutor.allCases)
    func droppingASuspendedResponse_cancelsIt(_ executor: TransferExecutor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { server in
            // Given
            let control = Internals.TransferControl()
            let window: Internals.FlowControlWindow

            do {
                let download = try await TransferHarness(executor).download(from: server, transferControl: control)
                window = try #require(download.step.bytes.flowControlWindowForTesting)

                control.suspend()
                _ = try await server.settled { server.bodyBytesWritten }

                // When: everything goes out of scope here.
                withExtendedLifetime(download) {}
            }

            // Then
            try await eventually(timeout: 30) { window.isReleasedForTesting && window.waitingCountForTesting == 0 }
            try await eventually(timeout: 30) { server.openConnections == 0 }
            #expect(control.gate.isReleasedForTesting)
            #expect(server.bodyBytesWritten < Self.largeBody)
        }
    }

    /// The connection is lost while suspended, and nothing can resume the download: it fails, as
    /// it always did, instead of hanging -- promptly on `.nio`, which learns about it right away,
    /// and once resumed on `.urlSession`, which only does when it reads again.
    @Test(arguments: TransferExecutor.allCases)
    func connectionLostWhileSuspended_withoutResumption_failsTheReader(_ executor: TransferExecutor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { server in
            // Given
            let control = Internals.TransferControl()
            let download = try await TransferHarness(executor).download(from: server, transferControl: control)
            let reader = BackgroundReader(download.step.bytes)

            try await eventually(timeout: 30) { reader.position > 0 }
            control.suspend()
            _ = try await server.settled { server.bodyBytesWritten }

            // When
            server.closeConnections()
            try await eventually { server.openConnections == 0 }
            control.resume()

            // Then
            #expect(try await reader.end(within: 30).isFailure)
            #expect(reader.verifier.isIntact)
            #expect(server.requests.count == 1)

            withExtendedLifetime(download) {}
        }
    }

    /// Pins down the limit of an in-flight suspension: a connection that moves nothing for longer
    /// than the client's own idle timeout is given up on by the client -- `timeoutIntervalForRequest`
    /// on `.urlSession`, the read timeout on `.nio` -- and, with nothing to resume it, the download
    /// fails with that timeout once the reader looks again. (On `.nio` the read timeout is off unless
    /// configured, and a suspension then lasts as long as the server lets it:
    /// `suspendMidBody_holdsTheConnectionUntilResumed` holds one for several seconds.)
    @Test(arguments: TransferExecutor.allCases)
    func suspensionLongerThanTheClientIdleTimeout_failsWithThatTimeout(_ executor: TransferExecutor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { server in
            // Given
            let control = Internals.TransferControl()
            let download = try await TransferHarness(executor, idleTimeout: 1).download(
                from: server,
                transferControl: control
            )
            let reader = BackgroundReader(download.step.bytes)

            try await eventually(timeout: 30) { reader.position > 0 }
            control.suspend()

            // When
            try await _Concurrency.Task.sleep(nanoseconds: 3_000_000_000)
            control.resume()

            // Then
            #expect(try await reader.end(within: 30).isFailure)
            #expect(executor.isIdleTimeout(reader.error), "\(String(describing: reader.error))")
            #expect(reader.verifier.isIntact)

            withExtendedLifetime(download) {}
        }
    }

    // MARK: - Reconnection

    /// A connection lost mid-body continues on a new one, from exactly the byte the reader got to,
    /// with `If-Range` guarding against a changed resource, and the reader never sees the seam.
    @Test(arguments: TransferExecutor.allCases, [false, true])
    func connectionLostMidBody_continuesWithRange(_ executor: TransferExecutor, isChunked: Bool) async throws {
        let length = 16 * 1_048_576
        let dropAt = 5_000_000

        try await withTransferServer(.init(length: length, isChunked: isChunked)) { server in
            // Given
            server.dropPlan = [dropAt]
            let control = Internals.TransferControl(resumption: Self.immediately)

            // When
            let download = try await TransferHarness(executor).download(from: server, transferControl: control)
            let reader = BackgroundReader(download.step.bytes)

            // Then
            #expect(try await reader.end() == .finished, "\(String(describing: reader.error))")
            #expect(reader.verifier.isIntact)
            #expect(reader.position == length)

            // The continuation starts where the *reader* got to, which can be short of what the
            // server got out: whatever was still in the client's buffers when the connection went
            // is dropped with it (observed: nothing on `.nio`, which delivers every part it read
            // before reporting the failure; up to ~750 KiB on `.urlSession`, where CFNetwork
            // discards what it had read ahead of `AsyncBytes`). An intact body of the right length
            // is what proves the seam lands on exactly the right byte.
            let requests = server.requests
            try #require(requests.count == 2)
            #expect(requests[0].bodyLength == dropAt)

            let resumedAt = try #require(Self.rangeStart(requests[1]))
            #expect((1...dropAt).contains(resumedAt))
            #expect(requests[1].header("If-Range") == "\"v1\"")
            #expect(requests[1].status == 206)
            reportMeasurement("\(executor) chunked=\(isChunked): dropped at \(dropAt), resumed at", resumedAt)

            withExtendedLifetime(download) {}
        }
    }

    /// Same, with `Last-Modified` as the only validator.
    @Test(arguments: TransferExecutor.allCases)
    func connectionLostMidBody_continuesWithRange_underLastModified(_ executor: TransferExecutor) async throws {
        let lastModified = "Sat, 26 Sep 2026 09:00:00 GMT"
        let resource = TransferServer.Resource(
            length: 8 * 1_048_576,
            validator: .lastModified(lastModified, date: "Sat, 26 Sep 2026 10:00:00 GMT")
        )

        try await withTransferServer(resource) { server in
            // Given
            server.dropPlan = [1_000_000]
            let control = Internals.TransferControl(resumption: Self.immediately)

            // When
            let download = try await TransferHarness(executor).download(from: server, transferControl: control)
            let reader = BackgroundReader(download.step.bytes)

            // Then
            #expect(try await reader.end() == .finished)
            #expect(reader.verifier.isIntact)
            #expect(reader.position == resource.length)
            #expect(server.requests.last?.header("If-Range") == lastModified)

            withExtendedLifetime(download) {}
        }
    }

    /// The resource changed between the lost connection and the continuation. The server honours
    /// `If-Range` by sending the whole new version; the download must fail rather than splice a
    /// single byte of it onto the old one.
    @Test(arguments: TransferExecutor.allCases)
    func resourceChangedBeforeTheContinuation_failsWithoutSplicing(_ executor: TransferExecutor) async throws {
        try await assertContinuationRejected(
            executor,
            resource: .init(length: 16 * 1_048_576),
            changeTo: .init(length: 16 * 1_048_576, seed: 1, validator: .entityTag("\"v2\"")),
            reason: .representationChanged,
            continuationStatus: 200
        )
    }

    /// A server that ignores `If-Range` answers with the requested range of the *new* version.
    /// The continuation's own validator gives it away.
    @Test(arguments: TransferExecutor.allCases)
    func serverIgnoringIfRange_isCaughtByTheValidator(_ executor: TransferExecutor) async throws {
        try await assertContinuationRejected(
            executor,
            resource: .init(length: 16 * 1_048_576, honorsIfRange: false),
            changeTo: .init(length: 16 * 1_048_576, seed: 1, validator: .entityTag("\"v2\""), honorsIfRange: false),
            reason: .validatorMismatch,
            continuationStatus: 206
        )
    }

    /// A server without range support sends the whole body again; that can't be spliced either.
    @Test(arguments: TransferExecutor.allCases)
    func serverWithoutRangeSupport_failsWithoutSplicing(_ executor: TransferExecutor) async throws {
        try await assertContinuationRejected(
            executor,
            resource: .init(length: 16 * 1_048_576, supportsRanges: false),
            changeTo: nil,
            reason: .representationChanged,
            continuationStatus: 200
        )
    }

    /// Without a strong validator a change of the resource couldn't be detected, so the download
    /// isn't resumed at all: it fails on the lost connection exactly as it did before, without a
    /// second request.
    @Test(arguments: TransferExecutor.allCases, [TransferServer.Validator.weakEntityTag("W/\"v1\""), .none])
    func withoutAStrongValidator_aLostConnectionFailsAsBefore(
        _ executor: TransferExecutor,
        validator: TransferServer.Validator
    ) async throws {
        try await withTransferServer(.init(length: 8 * 1_048_576, validator: validator)) { server in
            // Given
            server.dropPlan = [1_000_000]
            let control = Internals.TransferControl(resumption: Self.immediately)

            // When
            let download = try await TransferHarness(executor).download(from: server, transferControl: control)
            let reader = BackgroundReader(download.step.bytes)

            // Then
            #expect(try await reader.end().isFailure)
            #expect(reader.verifier.isIntact)
            #expect(reader.error.map { !($0 is Internals.DownloadResumptionMismatchError) } ?? false)

            try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            #expect(server.requests.count == 1)

            withExtendedLifetime(download) {}
        }
    }

    /// The flagship case: suspended for longer than the *server* is willing to keep an idle
    /// connection, then resumed. The suspension outlives the connection, and resuming picks the
    /// download up on a new one.
    ///
    /// Run once with the server giving up (its own idle timeout, the way nginx's `send_timeout` or a
    /// load balancer's would), and once with the client giving up (`timeoutIntervalForRequest` on
    /// `.urlSession`, the read timeout on `.nio`).
    @Test(arguments: TransferExecutor.allCases, ["server", "client"])
    func suspensionOutlivingTheConnection_reconnectsOnResume(_ executor: TransferExecutor, givesUp: String) async throws
    {
        let length = 64 * 1_048_576

        try await withTransferServer(.init(length: length)) { server in
            // Given
            let control = Internals.TransferControl(resumption: Self.immediately)
            let harness = TransferHarness(executor, idleTimeout: givesUp == "client" ? 1 : nil)

            if givesUp == "server" {
                server.stallTimeout = 1
            }

            let download = try await harness.download(from: server, transferControl: control)
            let reader = BackgroundReader(download.step.bytes)

            try await eventually(timeout: 30) { reader.position >= 1_048_576 }

            // When: suspended for three times the idle timeout.
            control.suspend()

            // Counted once a reconnection that was already under way when the suspension began has
            // had time to land: on a machine this loaded, the idle timeout can fire (and one
            // reconnection start) before the test even gets to `suspend()`, which says nothing
            // about the suspension.
            try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            let connectionsOnceSuspended = server.acceptedConnections

            try await _Concurrency.Task.sleep(nanoseconds: 2_500_000_000)

            // Nothing has been reconnected while suspended, whether or not the client noticed the
            // connection is gone yet.
            #expect(server.acceptedConnections == connectionsOnceSuspended)

            if givesUp == "server" {
                #expect(server.stalledConnections >= 1)
            }

            // The server's own idle timeout mustn't catch the continuation too.
            server.stallTimeout = nil
            control.resume()

            // Then
            #expect(try await reader.end() == .finished, "\(String(describing: reader.error))")
            #expect(reader.verifier.isIntact)
            #expect(reader.position == length)

            // At least the one reconnection the suspension forces. A client-side idle timeout this
            // short can also fire again on a continuation whose reader briefly falls behind (a
            // loaded machine), which reconnects once more by design, so the chain is what's checked:
            // every continuation asks for a point inside what its predecessor had sent, and gets it.
            let requests = server.requests
            try #require(requests.count >= 2)

            var previousStart = 0

            for (previous, next) in zip(requests, requests.dropFirst()) {
                let start = try #require(Self.rangeStart(next))
                #expect((previousStart + 1...previousStart + previous.bodyLength).contains(start))
                #expect(next.status == 206)
                previousStart = start
            }

            withExtendedLifetime(download) {}
        }
    }

    /// A server that keeps dropping the connection without sending anything is given up on after
    /// the policy's attempts, with the transport failure, not retried forever.
    @Test(arguments: TransferExecutor.allCases)
    func continuationsThatMakeNoProgress_areGivenUpOn(_ executor: TransferExecutor) async throws {
        try await withTransferServer(.init(length: 8 * 1_048_576)) { server in
            // Given
            server.dropPlan = [2_000_000, 0, 0, 0, 0, 0, 0]
            let control = Internals.TransferControl(resumption: Self.immediately)

            // When
            let download = try await TransferHarness(executor).download(from: server, transferControl: control)
            let reader = BackgroundReader(download.step.bytes)

            // Then
            #expect(try await reader.end().isFailure)
            #expect(reader.verifier.isIntact)
            #expect(reader.position <= 2_000_000)

            try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            let requests = server.requests
            #expect(requests.count == 1 + Self.immediately.maximumAttemptsWithoutProgress)

            // Every continuation asked for the same range: none of them got anywhere.
            #expect(Set(requests.dropFirst().map(Self.rangeStart)).count == 1)

            withExtendedLifetime(download) {}
        }
    }

    /// Everything arrived but the end of a chunked body. On `.nio` the missing terminating chunk
    /// is a transport failure, the continuation finds nothing left (`416`, complete length exactly
    /// what was delivered), and the download completes.
    ///
    /// `.urlSession` never gets that far, and pins down a pre-existing CFNetwork behaviour rather
    /// than anything added here: a chunked body cut off exactly on a chunk boundary, without its
    /// terminating chunk, is reported as *complete* (measured with a bare `URLSession`, both
    /// `bytes(from:)` and `data(from:)`; a cut mid-chunk fails with `.networkConnectionLost`). Here
    /// the body happens to be whole, so completing is right; for a body cut short on a boundary it
    /// is a silent truncation no reconnection can catch, since nothing ever fails.
    @Test(arguments: TransferExecutor.allCases)
    func lostJustBeforeTheEnd_completesOnAnUnsatisfiableRange(_ executor: TransferExecutor) async throws {
        let length = 1_048_576

        try await withTransferServer(.init(length: length, isChunked: true)) { server in
            // Given
            server.dropPlan = [length]
            let control = Internals.TransferControl(resumption: Self.immediately)

            // When
            let download = try await TransferHarness(executor).download(from: server, transferControl: control)
            let reader = BackgroundReader(download.step.bytes)

            // Then
            #expect(try await reader.end() == .finished, "\(String(describing: reader.error))")
            #expect(reader.verifier.isIntact)
            #expect(reader.position == length)

            switch executor {
            #if canImport(NIOCore)
            case .nio:
                #expect(server.requests.map(\.status) == [200, 416])
            #endif

            #if canImport(Darwin)
            case .urlSession:
                #expect(server.requests.map(\.status) == [200])
            #endif
            }

            withExtendedLifetime(download) {}
        }
    }

    /// Cancelled after the connection was lost, while the continuation is still held back by a
    /// suspension: the download fails right away, and no continuation is ever sent.
    @Test(arguments: TransferExecutor.allCases)
    func cancelWhileWaitingToReconnect_failsTheReaderWithoutReconnecting(_ executor: TransferExecutor) async throws {
        try await withTransferServer(.init(length: Self.largeBody)) { server in
            // Given
            let control = Internals.TransferControl(resumption: Self.immediately)
            let download = try await TransferHarness(executor).download(from: server, transferControl: control)
            let reader = BackgroundReader(download.step.bytes)

            try await eventually(timeout: 30) { reader.position > 0 }
            control.suspend()
            _ = try await server.settled { server.bodyBytesWritten }

            server.closeConnections()
            try await eventually { server.openConnections == 0 }
            try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)

            // When
            download.task.seed()

            // Then
            #expect(try await reader.end(within: 30).isFailure)

            try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            #expect(server.requests.count == 1)
            #expect(control.gate.isReleasedForTesting)
        }
    }

    // MARK: - Private methods

    /// `N` from a continuation's `Range: bytes=N-`.
    private static func rangeStart(_ request: TransferServer.ReceivedRequest) -> Int? {
        guard let range = request.header("Range"), range.hasPrefix("bytes="), range.hasSuffix("-") else {
            return nil
        }

        return Int(range.dropFirst("bytes=".count).dropLast())
    }

    /// Loses the connection while suspended, optionally changes the resource on the server,
    /// resumes, and expects the continuation to be rejected for `reason` with not one byte of it
    /// reaching the reader.
    private func assertContinuationRejected(
        _ executor: TransferExecutor,
        resource: TransferServer.Resource,
        changeTo newResource: TransferServer.Resource?,
        reason: Internals.DownloadResumptionMismatchError.Reason,
        continuationStatus: Int
    ) async throws {
        try await withTransferServer(resource) { server in
            // Given
            let control = Internals.TransferControl(resumption: Self.immediately)
            let download = try await TransferHarness(executor).download(from: server, transferControl: control)
            let reader = BackgroundReader(download.step.bytes, seed: resource.seed)

            try await eventually(timeout: 30) { reader.position > 0 }
            control.suspend()
            _ = try await server.settled { server.bodyBytesWritten }

            server.closeConnections()
            try await eventually { server.openConnections == 0 }

            if let newResource {
                server.resource = newResource
            }

            // When
            control.resume()

            // Then
            #expect(try await reader.end().isFailure)
            #expect(reader.error as? Internals.DownloadResumptionMismatchError == .init(reason))

            // Every byte the reader got is the original version's, and no more of it than the
            // original exchange delivered.
            #expect(reader.verifier.isIntact)
            #expect(reader.position <= server.requests.first?.bodyLength ?? .max)

            let requests = server.requests
            try #require(requests.count == 2)
            #expect(requests[1].status == continuationStatus)

            withExtendedLifetime(download) {}
        }
    }
}
