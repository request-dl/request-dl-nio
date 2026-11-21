//
// See LICENSE for this package's licensing information.
//

#if canImport(Darwin)

import Foundation
@_spi(Testing) import SwiftAsyncStream
import Testing

@testable @_spi(Testing) import RequestDLInternals
@testable import RequestDLTestSupport

/// What a `.urlSession` download that lost its connection holds while it waits to reconnect.
///
/// A resumable download whose connection drops while its execution is suspended only reconnects once
/// it is resumed, which can be hours later. With `maximumConcurrentConnections` set, the slot it
/// was admitted with must not stay taken for that long: nothing of it is on the network, and every
/// other request of the session would wait for a `resume()` that may never come. This is what the
/// `.nio` executor does (`Internals.NIODownloadReconnection` waits without a slot and asks for a new
/// one), and the continuation takes a slot again, cancellably, before it goes out.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsURLSessionClientReconnectionSlotTests {

    private static let immediately = Internals.DownloadResumptionPolicy(maximumAttemptsWithoutProgress: 3, delay: 0)

    /// Cut after this many body bytes: less than the reading mode's first chunk, so the body fails
    /// before the pump would wait on the (suspended) window, and the download goes straight to
    /// waiting for the resume.
    private static let droppedAt = 1_000

    private func makeClient() throws -> Internals.URLSessionClient {
        // The transport's own idle timer is out of the way, as `buildURLSessionConfiguration()` leaves
        // it: how long an execution may stay silent is `Internals.IdleDeadline`'s to decide.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = TimeInterval(Int64.max) / 1_000_000_000

        return try Internals.URLSessionClient(configuration: configuration, maximumConcurrentConnections: 1)
    }

    private func startDownload(
        _ client: Internals.URLSessionClient,
        from server: TransferServer,
        path: String = "/resource",
        transferControl: Internals.TransferControl?
    ) async throws -> (task: SessionTask, step: Internals.DownloadStep) {
        let task = try await client.execute(
            request: URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(server.port)\(path)"))),
            readingMode: .length(65_536),
            uploadingBytes: .zero,
            decompression: .disabled,
            cache: nil,
            logger: nil,
            transferControl: transferControl
        )

        for try await step in task.response {
            if case .download(let download) = step {
                return (task, download)
            }
        }

        throw AnyError()
    }

    // MARK: - While waiting

    /// Suspended, the download loses its connection and goes to wait for the resume. Its slot is free
    /// meanwhile, so another request of the same session (a limit of one) goes through, and the download
    /// still ends up complete once resumed.
    @Test
    func download_whenWaitingToReconnect_doesNotKeepItsSlot() async throws {
        let length = 8 * 1_048_576

        try await withTransferServer(.init(length: length)) { server in
            // Given: a limit of one, and a download that is suspended from the start and cut early.
            server.dropPlan = [Self.droppedAt]

            let client = try makeClient()
            let semaphore = try #require(client.connectionSemaphoreForTesting)
            let control = Internals.TransferControl(resumption: Self.immediately)
            control.suspend()

            // When
            let download = try await startDownload(client, from: server, transferControl: control)
            let reader = BackgroundReader(download.step.bytes)

            // Then: the slot is given back while it waits.
            try await eventually(timeout: 15) { semaphore.availablePermits == 1 }
            #expect(reader.outcome == nil)

            // And another request does not wait for it.
            let other = try await completing(within: 30) {
                try await client.execute(
                    request: URLRequest(url: try #require(URL(string: "http://127.0.0.1:\(server.port)/other")))
                )
            }

            #expect(other.head.status.code == 200)
            #expect(other.body.count == length)

            // When: resumed, it takes a slot again and carries on.
            control.resume()

            // Then
            #expect(try await reader.end() == .finished, "\(String(describing: reader.error))")
            #expect(reader.verifier.isIntact)
            #expect(reader.position == length)

            try await eventually(timeout: 15) { semaphore.availablePermits == 1 && !client.isRunning }

            try await awaitRecordedRequests(server, atLeast: 3)
            #expect(server.requests.count == 3)

            withExtendedLifetime(download) {}
        }
    }

    // MARK: - While waiting for the slot again

    /// Resumed while another request holds the only slot: the continuation waits for it, and
    /// cancelling that wait ends the download without a continuation ever being sent and without
    /// disturbing the slot of the request that has it.
    @Test
    func download_whenCancelledWhileWaitingForItsSlotAgain_endsWithoutReconnecting() async throws {
        try await withTransferServer(.init(length: 64 * 1_048_576)) { server in
            // Given: the download waiting to reconnect, with its slot given back, and that slot
            // then taken by another request that stays in flight (nobody reads its body).
            server.dropPlan = [Self.droppedAt]

            let client = try makeClient()
            let semaphore = try #require(client.connectionSemaphoreForTesting)
            let control = Internals.TransferControl(resumption: Self.immediately)
            control.suspend()

            let download = try await startDownload(client, from: server, transferControl: control)
            let reader = BackgroundReader(download.step.bytes)

            try await eventually(timeout: 15) { semaphore.availablePermits == 1 }

            let holder = try await startDownload(client, from: server, path: "/holder", transferControl: nil)
            #expect(semaphore.availablePermits == 0)

            // When: resumed, so it asks for a slot again, and cancelled while it waits for one.
            control.resume()
            try await semaphore.waitForWaiters(1, timeout: 30)

            download.task.seed()

            // Then
            #expect(try await reader.end(within: 30).isFailure)
            try await semaphore.waitForWaiters(0, timeout: 30)

            // The holder kept its slot throughout, and gives it back when it is over.
            #expect(semaphore.availablePermits == 0)

            holder.task.seed()
            try await eventually(timeout: 15) { semaphore.availablePermits == 1 && !client.isRunning }

            try await awaitRecordedRequests(server, atLeast: 2)
            #expect(server.requests.count == 2)

            withExtendedLifetime((download, holder)) {}
        }
    }
}

#endif
