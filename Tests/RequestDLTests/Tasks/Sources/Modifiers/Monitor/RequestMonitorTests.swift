//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
#endif

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A ``RequestMonitor`` that records everything it is told, and can be slowed down.
final class RecordingMonitor: RequestMonitor, @unchecked Sendable {

    struct Transfer: Sendable, Equatable {
        let execution: UUID
        let bytes: Int
        let total: Int
        let expected: Int?
    }

    private let lock = Lock()
    private var _uploads: [Transfer] = []
    private var _downloads: [Transfer] = []
    private var _states: [(execution: RequestExecution, state: RequestState)] = []

    /// Microseconds each progress call takes, to model a monitor slower than the network.
    let progressDelay: UInt32

    init(progressDelay: UInt32 = 0) {
        self.progressDelay = progressDelay
    }

    var uploads: [Transfer] { lock.withLock { _uploads } }
    var downloads: [Transfer] { lock.withLock { _downloads } }
    var executions: [RequestExecution] { lock.withLock { _states.map(\.execution) } }

    /// The states of one execution, or of every one when `execution` is `nil`, by name.
    func states(of execution: RequestExecution? = nil) -> [String] {
        lock.withLock {
            _states
                .filter { execution == nil || $0.execution == execution }
                .map { Self.name($0.state) }
        }
    }

    var failure: (any Error)? {
        lock.withLock {
            for entry in _states {
                if case .failed(let error) = entry.state {
                    return error
                }
            }

            return nil
        }
    }

    var hasEnded: Bool {
        let states = states()
        return states.contains("finished") || states.contains("failed")
    }

    func request(_ execution: RequestExecution, didUpload bytes: Int, total: Int, of expected: Int?) {
        if progressDelay > 0 {
            usleep(progressDelay)
        }

        lock.withLock {
            _uploads.append(.init(execution: execution.id, bytes: bytes, total: total, expected: expected))
        }
    }

    func request(_ execution: RequestExecution, didDownload bytes: Int, total: Int, of expected: Int?) {
        if progressDelay > 0 {
            usleep(progressDelay)
        }

        lock.withLock {
            _downloads.append(.init(execution: execution.id, bytes: bytes, total: total, expected: expected))
        }
    }

    func request(_ execution: RequestExecution, didChange state: RequestState) {
        lock.withLock { _states.append((execution, state)) }
    }

    static func name(_ state: RequestState) -> String {
        switch state {
        case .started:
            return "started"
        case .suspended:
            return "suspended"
        case .resumed:
            return "resumed"
        case .reconnecting(let attempt):
            return "reconnecting(\(attempt))"
        case .finished:
            return "finished"
        case .failed:
            return "failed"
        }
    }
}

/// End-to-end coverage of `.monitor(_:)` through the public API, against a real
/// ``TransferServer`` on each executor.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct RequestMonitorTests {

    private static let length = 8 * 1_048_576

    private typealias Executor = TransferTestExecutor

    private static func download(from server: TransferServer, executor: Executor) -> DownloadTask<some Property> {
        DownloadTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path("/resource")
            executor.session
        }
    }

    private static func data(from server: TransferServer, executor: Executor) -> AnyTask<Data> {
        DataTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path("/resource")
            executor.session
        }
        .extractPayload()
        .eraseToAnyTask()
    }

    // MARK: - Progress and lifecycle

    @Test(arguments: Executor.allCases)
    private func aDownload_reportsItsProgressAndLifecycle(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            let monitor = RecordingMonitor()

            // When
            let data = try await Self.data(from: server, executor: executor)
                .monitor(monitor)
                .result()

            try await eventually(timeout: 30) { monitor.hasEnded }

            // Then
            #expect(data.count == Self.length)
            #expect(monitor.states() == ["started", "finished"])

            let downloads = monitor.downloads
            #expect(downloads.last?.total == Self.length)
            #expect(downloads.map(\.bytes).reduce(0, +) == Self.length)
            #expect(downloads.allSatisfy { $0.expected == Self.length })
            #expect(downloads.map(\.total) == downloads.map(\.total).sorted())
            #expect(Set(downloads.map(\.execution)).count == 1)

            // Each step says what it added and where that leaves the total.
            var running = 0
            for step in downloads {
                running += step.bytes
                #expect(step.total == running)
            }

            #expect(monitor.uploads.isEmpty)
        }
    }

    @Test(arguments: Executor.allCases)
    private func theExecution_describesTheRequest(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: 1_024)) { server in
            // Given
            let recorded = LockedValueBox<RequestExecution?>(nil)

            struct Capture: RequestMonitor {
                let recorded: LockedValueBox<RequestExecution?>

                func request(_ execution: RequestExecution, didChange state: RequestState) {
                    recorded.withLockedValue { $0 = execution }
                }
            }

            // When
            _ = try await Self.data(from: server, executor: executor)
                .monitor(Capture(recorded: recorded))
                .result()

            try await eventually { recorded.withLockedValue { $0 != nil } }

            // Then
            let execution = try #require(recorded.withLockedValue { $0 })
            #expect(execution.method == "GET")
            #expect(execution.url.hasSuffix("/resource"))
            #expect(execution.url.contains("127.0.0.1:\(server.port)"))
        }
    }

    @Test(arguments: Executor.allCases)
    private func anUpload_reportsItsProgress(_ executor: Executor) async throws {
        let size = 6 * 1_048_576

        try await withTransferServer(.init(length: 1_024)) { server in
            // Given
            let monitor = RecordingMonitor()
            var body = Data()

            var position = 0
            while position < size {
                let count = min(65_536, size - position)
                body.append(contentsOf: TransferServer.uploadBody(from: position, count: count))
                position += count
            }

            // When
            _ = try await UploadTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Path("/upload")
                RequestMethod(.put)
                executor.session
                Payload(data: body)
            }
            .collectData()
            .extractPayload()
            .monitor(monitor)
            .result()

            try await eventually(timeout: 30) { monitor.hasEnded }

            // Then
            let uploads = monitor.uploads
            #expect(uploads.last?.total == size)
            #expect(uploads.map(\.bytes).reduce(0, +) == size)
            #expect(uploads.allSatisfy { $0.expected == size })
            #expect(monitor.states() == ["started", "finished"])
        }
    }

    /// The point of measuring on the network: a download's progress runs while nobody reads its
    /// body, up to what the transport buffers ahead, and finishes counting the whole body once it
    /// is read.
    @Test(arguments: Executor.allCases)
    private func progress_isMeasuredOnTheNetwork_notWhereTheBodyIsRead(_ executor: Executor) async throws {
        let length = 64 * 1_048_576

        try await withTransferServer(.init(length: length)) { server in
            // Given
            let monitor = RecordingMonitor()

            // When: the response is here, and not one byte of its body has been read.
            let result = try await Self.download(from: server, executor: executor)
                .monitor(monitor)
                .result()

            try await eventually(timeout: 30) { (monitor.downloads.last?.total ?? 0) > 0 }

            let stalledAt = try await server.settled { monitor.downloads.last?.total ?? 0 }

            // Then: bytes are being counted, held back only by what the transport buffers.
            #expect(stalledAt > 0)
            #expect(stalledAt < length / 2)
            #expect(monitor.states() == ["started"])

            // When: it is read to the end.
            var read = 0
            for try await chunk in result.payload {
                read += chunk.count
            }

            try await eventually(timeout: 30) { monitor.hasEnded }

            // Then
            #expect(read == length)
            #expect(monitor.downloads.last?.total == length)
            #expect(monitor.states() == ["started", "finished"])
        }
    }

    // MARK: - Failure

    @Test(arguments: Executor.allCases)
    private func aFailedDownload_isReportedAsFailed(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            server.dropPlan = [1_000_000]
            let monitor = RecordingMonitor()

            // When
            await #expect(throws: (any Error).self) {
                _ = try await Self.data(from: server, executor: executor)
                    .monitor(monitor)
                    .result()
            }

            try await eventually(timeout: 30) { monitor.hasEnded }

            // Then
            #expect(monitor.states() == ["started", "failed"])
            #expect(monitor.failure != nil)
        }
    }

    @Test(arguments: Executor.allCases)
    private func aRequestThatNeverGetsSent_isReportedAsStartedThenFailed(_ executor: Executor) async throws {
        // Given: nothing listens on this port.
        let monitor = RecordingMonitor()

        // When
        await #expect(throws: (any Error).self) {
            _ = try await DataTask {
                BaseURL(.http, host: "127.0.0.1:1")
                Path("/resource")
                executor.session

                // Some transports keep retrying a refused connection for a while; the request is
                // failing either way, and this only keeps the test from waiting on them.
                Timeout(.seconds(3), for: .resource)
            }
            .monitor(monitor)
            .result()
        }

        try await eventually(timeout: 30) { monitor.hasEnded }

        // Then
        #expect(monitor.states() == ["started", "failed"])
    }

    // MARK: - With a controller and a resumption policy

    @Test(arguments: Executor.allCases)
    private func suspendAndResume_areReportedInOrder(_ executor: Executor) async throws {
        let length = 64 * 1_048_576

        try await withTransferServer(.init(length: length)) { server in
            // Given
            let monitor = RecordingMonitor()
            let controller = RequestController()

            let running = _Concurrency.Task {
                try await Self.data(from: server, executor: executor)
                    .monitor(monitor)
                    .controller(controller)
                    .result()
            }

            try await eventually(timeout: 30) { (monitor.downloads.last?.total ?? 0) >= 1_048_576 }

            // When
            controller.suspend()
            let stalledAt = try await server.settled { monitor.downloads.last?.total ?? 0 }

            // Then: what the monitor counts stops too, because the transfer did.
            #expect(stalledAt < length / 2)
            #expect(monitor.states() == ["started", "suspended"])

            try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            #expect((monitor.downloads.last?.total ?? 0) == stalledAt)

            // When
            controller.resume()
            let data = try await running.value

            try await eventually(timeout: 30) { monitor.hasEnded }

            // Then
            #expect(data.count == length)
            #expect(monitor.states() == ["started", "suspended", "resumed", "finished"])
            #expect(monitor.downloads.last?.total == length)
        }
    }

    /// Attaching to a controller that is already suspended must not report the suspension before
    /// the request has started.
    @Test(arguments: Executor.allCases)
    private func startedWhileSuspended_reportsStartedFirst(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            let monitor = RecordingMonitor()
            let controller = RequestController()
            controller.suspend()

            let running = _Concurrency.Task {
                try await Self.data(from: server, executor: executor)
                    .monitor(monitor)
                    .controller(controller)
                    .result()
            }

            try await eventually(timeout: 30) { monitor.states().count >= 2 }

            // Then
            #expect(monitor.states() == ["started", "suspended"])

            // When
            controller.resume()
            _ = try await running.value
            try await eventually(timeout: 30) { monitor.hasEnded }

            // Then
            #expect(monitor.states() == ["started", "suspended", "resumed", "finished"])
        }
    }

    @Test(arguments: Executor.allCases)
    private func aReconnection_isReportedAndItsBytesCounted(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            server.dropPlan = [1_000_000]
            let monitor = RecordingMonitor()

            // When
            let data = try await Self.data(from: server, executor: executor)
                .resumingDownloads(.enabled(delay: 0))
                .monitor(monitor)
                .result()

            try await eventually(timeout: 30) { monitor.hasEnded }

            // Then: one download, counted once across the two connections.
            #expect(data.count == Self.length)
            #expect(monitor.states() == ["started", "reconnecting(1)", "finished"])
            #expect(monitor.downloads.last?.total == Self.length)
            #expect(monitor.downloads.map(\.bytes).reduce(0, +) == Self.length)
        }
    }

    // MARK: - Several requests, several monitors, a slow monitor

    @Test(arguments: Executor.allCases)
    private func aGroup_tellsItsExecutionsApart(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            let monitor = RecordingMonitor()

            // When
            let results = try await GroupTask([0, 1, 2]) { _ in
                Self.data(from: server, executor: executor)
                    .map(\.count)
                    .eraseToAnyTask()
            }
            .monitor(monitor)
            .result()

            try await eventually(timeout: 30) { monitor.states().filter { $0 == "finished" }.count == 3 }

            // Then
            #expect(results.count == 3)

            let executions = Set(monitor.executions.map(\.id))
            #expect(executions.count == 3)

            for id in executions {
                let steps = monitor.downloads.filter { $0.execution == id }
                #expect(steps.last?.total == Self.length)
                #expect(steps.map(\.bytes).reduce(0, +) == Self.length)
            }
        }
    }

    @Test(arguments: Executor.allCases)
    private func severalMonitors_areAllTold(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: 1_048_576)) { server in
            // Given
            let first = RecordingMonitor()
            let second = RecordingMonitor()

            // When
            _ = try await Self.data(from: server, executor: executor)
                .monitor(first)
                .monitor(second)
                .result()

            try await eventually(timeout: 30) { first.hasEnded && second.hasEnded }

            // Then
            #expect(first.downloads.last?.total == 1_048_576)
            #expect(second.downloads.last?.total == 1_048_576)
            #expect(first.states() == ["started", "finished"])
            #expect(second.states() == ["started", "finished"])
        }
    }

    /// A monitor that is slower than the network neither slows the transfer nor piles up
    /// progress: it sees fewer, larger steps that still add up to the whole body.
    @Test(arguments: Executor.allCases)
    private func aSlowMonitor_neitherSlowsTheTransferNorQueuesProgress(_ executor: Executor) async throws {
        let length = 32 * 1_048_576

        try await withTransferServer(.init(length: length)) { server in
            // Given: 100 ms per progress call.
            let monitor = RecordingMonitor(progressDelay: 100_000)

            // When
            let data = try await Self.data(from: server, executor: executor)
                .monitor(monitor)
                .result()

            // Then: the transfer didn't wait for the monitor, which is still working through what
            // it was handed.
            #expect(data.count == length)

            try await eventually(timeout: 60) { monitor.hasEnded }

            let downloads = monitor.downloads
            #expect(downloads.last?.total == length)
            #expect(downloads.map(\.bytes).reduce(0, +) == length)

            // Delivered in far fewer steps than the transport handed bytes over in: a 32 MiB body
            // arrives in thousands of pieces.
            #expect(downloads.count < 200)
        }
    }
}
