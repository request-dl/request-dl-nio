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

/// End-to-end coverage for suspending and resuming an *upload* in flight, on both executors, by
/// the same test bodies: `.nio` pauses `Internals.StreamWriterSequence` between chunks, and
/// `.urlSession` pauses `Internals.URLSessionUploadBodyPump`'s writes into a bound stream pair.
///
/// The server checks every byte it receives against the pattern the body was generated from, so a
/// suspension that lost, repeated or reordered anything -- at the pause, or across a resend -- fails
/// `isBodyIntact`, and it counts what arrives as it arrives, so an upload that kept going while
/// "suspended" shows up as that count moving.
///
/// And what these tests deliberately *don't* do: resume an upload across a lost connection. There's
/// no universal way to learn how much of a body a server received, so a lost upload fails, and is
/// never silently sent again from the start.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct InternalsTransferControlUploadTests {

    /// Past `Internals.URLSessionUploadFile.inMemoryThreshold`, so `.urlSession` pumps from a file;
    /// the smaller size stays in memory.
    private static let sizes = [6 * 1_048_576, 24 * 1_048_576]

    /// The core guarantee: nothing more reaches the server while suspended, and after resuming
    /// the server receives exactly the body, every byte once, in order.
    ///
    /// What can still arrive once suspended is whatever the client's kernel already accepted: its
    /// send buffer autotunes up to `net.inet.tcp.autosndbufmax` (4 MiB on macOS), plus the
    /// server's small receive buffer and one piece in flight. So the suspension is triggered by the
    /// server itself, from its own thread, at an exact byte early in the body, and the server reads
    /// slower than loopback would (`uploadReadDelay`): even the smaller body then stays well clear
    /// of that bound. Triggered from the test's own task instead, under full-suite load, the task
    /// was once scheduled so late the whole 6 MiB was already in -- which says nothing about the
    /// suspension either way.
    @Test(arguments: TransferExecutor.allCases, sizes)
    func suspendMidUpload_stopsTheBodyUntilResumed(_ executor: TransferExecutor, size: Int) async throws {
        try await withTransferServer(.init(length: 1_024)) { server in
            // Given
            let control = Internals.TransferControl()
            let suspendedAt = LockedValueBox<Int?>(nil)

            server.uploadReadDelay = 2_000
            server.onUploadProgress = { received in
                guard received >= 262_144, suspendedAt.withLockedValue({ $0 == nil }) else {
                    return
                }

                // When
                suspendedAt.withLockedValue { $0 = received }
                control.suspend()
            }

            let (task, owner) = try await TransferHarness(executor).upload(
                to: server,
                size: size,
                transferControl: control
            )

            let completion = Task {
                try await Self.complete(task)
            }

            try await eventually(timeout: 30) { suspendedAt.withLockedValue { $0 != nil } }
            server.onUploadProgress = nil

            let receivedAtSuspension = try #require(suspendedAt.withLockedValue { $0 })
            let stalledAt = try await server.settled { server.uploadBytesReceived }

            // Then: what was already in the socket buffers still arrives, and nothing more.
            #expect(stalledAt < size)
            #expect(stalledAt - receivedAtSuspension <= 4_718_592)

            try await _Concurrency.Task.sleep(nanoseconds: 2_000_000_000)
            #expect(server.uploadBytesReceived == stalledAt)

            reportMeasurement(
                "\(executor) upload (\(size)): bytes in after suspend()",
                stalledAt - receivedAtSuspension
            )

            // When
            control.resume()

            // Then
            let uploaded = try await completing(within: 60) { try await completion.value }
            #expect(uploaded.status == 200)

            try await awaitRecordedRequests(server, atLeast: 1)
            let requests = server.requests
            #expect(requests.count == 1)
            #expect(requests.first?.bodyLength == size)
            #expect(requests.first?.isBodyIntact == true)
            #expect(requests.first?.isBodyComplete == true)
            #expect(uploaded.progress == size)

            withExtendedLifetime(owner) {}
        }
    }

    /// Suspended before anything is sent: not a single body byte reaches the server until resumed.
    @Test(arguments: TransferExecutor.allCases)
    func suspendBeforeTheUpload_sendsNoBodyUntilResumed(_ executor: TransferExecutor) async throws {
        let size = 2 * 1_048_576

        try await withTransferServer(.init(length: 1_024)) { server in
            // Given
            let control = Internals.TransferControl()
            control.suspend()

            // When
            let (task, owner) = try await TransferHarness(executor).upload(
                to: server,
                size: size,
                transferControl: control
            )

            let completion = Task {
                try await Self.complete(task)
            }

            try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)

            // Then
            #expect(server.uploadBytesReceived == 0)

            control.resume()

            let uploaded = try await completing(within: 60) { try await completion.value }
            #expect(uploaded.status == 200)
            try await awaitRecordedRequests(server, atLeast: 1)
            #expect(server.requests.first?.bodyLength == size)
            #expect(server.requests.first?.isBodyIntact == true)

            withExtendedLifetime(owner) {}
        }
    }

    /// Cancelling a suspended upload ends it right away; the server gets a truncated body and a
    /// closed connection, never the rest.
    @Test(arguments: TransferExecutor.allCases)
    func cancelWhileSuspended_endsTheUpload(_ executor: TransferExecutor) async throws {
        let size = 24 * 1_048_576

        try await withTransferServer(.init(length: 1_024)) { server in
            // Given
            let control = Internals.TransferControl()
            let (task, owner) = try await TransferHarness(executor).upload(
                to: server,
                size: size,
                transferControl: control
            )

            let completion = Task {
                try await Self.complete(task)
            }

            try await eventually(timeout: 30) { server.uploadBytesReceived >= 1_048_576 }
            control.suspend()
            _ = try await server.settled { server.uploadBytesReceived }

            // When
            task.seed()

            // Then
            let outcome = try await completing(within: 30) { () -> String in
                do {
                    _ = try await completion.value
                    return "completed"
                } catch {
                    return "failed"
                }
            }

            #expect(outcome == "failed")
            try await eventually(timeout: 30) { server.openConnections == 0 }
            #expect(server.uploadBytesReceived < size)
            try await awaitRecordedRequests(server, atLeast: 1)
            #expect(server.requests.first?.isBodyComplete == false)
            #expect(control.gate.isReleasedForTesting)

            withExtendedLifetime(owner) {}
        }
    }

    /// Pins down where the two executors' *transports* differ, not the mechanism: `.urlSession`
    /// applies `timeoutIntervalForRequest` while an upload is idle too, so a suspension longer than
    /// it fails the request; `.nio` has no client-side idle timeout on the request body at all
    /// (AsyncHTTPClient only starts its read timeout once the request is fully sent, and RequestDL
    /// sets no write timeout), so the same suspension survives. Either way the server's own idle
    /// timeout still applies -- see `serverGivingUpOnASuspendedUpload_failsItWithoutResending`.
    @Test(arguments: TransferExecutor.allCases)
    func suspensionLongerThanTheClientIdleTimeout(_ executor: TransferExecutor) async throws {
        let size = 24 * 1_048_576

        try await withTransferServer(.init(length: 1_024)) { server in
            // Given
            let control = Internals.TransferControl()
            let (task, owner) = try await TransferHarness(executor, idleTimeout: 1).upload(
                to: server,
                size: size,
                transferControl: control
            )

            let completion = Task {
                try await Self.complete(task)
            }

            try await eventually(timeout: 30) { server.uploadBytesReceived >= size / 4 }

            // When
            control.suspend()
            try await _Concurrency.Task.sleep(nanoseconds: 3_000_000_000)
            control.resume()

            // Then
            let result = try await completing(within: 60) { () -> Result<Uploaded, ErrorBoxError> in
                do {
                    return .success(try await completion.value)
                } catch {
                    return .failure(ErrorBoxError(ErrorBox(error)))
                }
            }

            switch executor {
            #if canImport(NIOCore)
            case .nio:
                #expect(try result.get().status == 200)
                try await awaitRecordedRequests(server, atLeast: 1)
                #expect(server.requests.first?.isBodyIntact == true)
                #expect(server.requests.first?.bodyLength == size)
            #endif

            #if canImport(Darwin)
            case .urlSession:
                guard case .failure(let failure) = result else {
                    Issue.record("Expected the upload to time out")
                    return
                }

                #expect(executor.isIdleTimeout(failure.box.error), "\(String(describing: failure.box.error))")
                #expect(server.requests.first?.isBodyComplete == false)
            #endif
            }

            withExtendedLifetime(owner) {}
        }
    }

    /// The server gives up on an upload suspended for longer than it's willing to wait. The upload
    /// fails once resumed, and it is *not* sent again: resuming an upload across a lost connection
    /// needs a server-side protocol RequestDL doesn't assume.
    @Test(arguments: TransferExecutor.allCases)
    func serverGivingUpOnASuspendedUpload_failsItWithoutResending(_ executor: TransferExecutor) async throws {
        let size = 24 * 1_048_576

        try await withTransferServer(.init(length: 1_024)) { server in
            // Given: a download resumption policy too, which must not apply to an upload.
            let control = Internals.TransferControl(resumption: .init(maximumAttemptsWithoutProgress: 3, delay: 0))
            let (task, owner) = try await TransferHarness(executor).upload(
                to: server,
                size: size,
                transferControl: control
            )

            let completion = Task {
                try await Self.complete(task)
            }

            try await eventually(timeout: 30) { server.uploadBytesReceived >= size / 4 }

            // When
            server.stallTimeout = 1
            control.suspend()
            try await eventually(timeout: 30) { server.stalledConnections == 1 }
            control.resume()

            // Then
            let outcome = try await completing(within: 60) { () -> String in
                do {
                    _ = try await completion.value
                    return "completed"
                } catch {
                    return "failed"
                }
            }

            #expect(outcome == "failed")

            try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            try await awaitRecordedRequests(server, atLeast: 1)
            #expect(server.requests.count == 1)
            #expect(server.requests.first?.isBodyComplete == false)
            #expect(server.requests.first?.isBodyIntact == true)

            withExtendedLifetime(owner) {}
        }
    }

    /// A connection cut mid-upload fails the upload, once, even with a resumption policy.
    @Test(arguments: TransferExecutor.allCases)
    func connectionLostMidUpload_failsWithoutResending(_ executor: TransferExecutor) async throws {
        let size = 8 * 1_048_576

        try await withTransferServer(.init(length: 1_024)) { server in
            // Given
            server.uploadDropPlan = [2_000_000]
            let control = Internals.TransferControl(resumption: .init(maximumAttemptsWithoutProgress: 3, delay: 0))

            // When
            let (task, owner) = try await TransferHarness(executor).upload(
                to: server,
                size: size,
                transferControl: control
            )

            // Then
            let outcome = try await completing(within: 60) { () -> String in
                do {
                    _ = try await Self.complete(task)
                    return "completed"
                } catch {
                    return "failed"
                }
            }

            #expect(outcome == "failed")

            try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            try await awaitRecordedRequests(server, atLeast: 1)
            #expect(server.requests.count == 1)
            #expect(server.requests.first?.bodyLength == 2_000_000)
            #expect(server.requests.first?.isBodyIntact == true)

            withExtendedLifetime(owner) {}
        }
    }

    #if canImport(Darwin)
    /// A 307 makes `URLSession` ask for the body again (`needNewBodyStream`); the pump answers with
    /// a fresh stream from the first byte, and a suspension applies to the resend like to the
    /// original send.
    @Test
    func urlSessionResendAfterA307_sendsTheWholeBodyAgain_andStaysSuspendable() async throws {
        let size = 24 * 1_048_576

        try await withTransferServer(.init(length: 1_024)) { server in
            // Given
            server.redirectsFirstUpload = true
            let control = Internals.TransferControl()

            let (task, owner) = try await TransferHarness(.urlSession).upload(
                to: server,
                size: size,
                transferControl: control
            )

            let completion = Task {
                try await Self.complete(task)
            }

            // Suspended during the resend.
            try await eventually(timeout: 60) { server.uploadBytesReceived >= size + size / 4 }
            control.suspend()

            let stalledAt = try await server.settled { server.uploadBytesReceived }
            try await _Concurrency.Task.sleep(nanoseconds: 1_000_000_000)
            #expect(server.uploadBytesReceived == stalledAt)
            #expect(stalledAt < 2 * size)

            // When
            control.resume()

            // Then
            let uploaded = try await completing(within: 60) { try await completion.value }
            #expect(uploaded.status == 200)

            try await awaitRecordedRequests(server, atLeast: 2)
            let requests = server.requests
            #expect(requests.map(\.path) == ["/upload", "/final"])
            #expect(requests.map(\.bodyLength) == [size, size])
            #expect(requests.map(\.isBodyIntact) == [true, true])
            #expect(requests.map { $0.header("Content-Length") } == [String(size), String(size)])

            withExtendedLifetime(owner) {}
        }
    }
    #endif

    // MARK: - Private

    struct Uploaded: Sendable {
        let status: UInt
        let progress: Int
    }

    struct ErrorBoxError: Error {
        let box: ErrorBox

        init(_ box: ErrorBox) {
            self.box = box
        }
    }

    /// Reads a whole upload response: its progress, its head, and its (small) body.
    private static func complete(_ task: SessionTask) async throws -> Uploaded {
        var progress = 0
        var status: UInt = 0

        for try await step in task.response {
            switch step {
            case .upload(let upload):
                progress += upload.chunkSize
            case .download(let download):
                status = download.head.status.code

                for try await _ in download.bytes {}
            }
        }

        return Uploaded(status: status, progress: progress)
    }
}
