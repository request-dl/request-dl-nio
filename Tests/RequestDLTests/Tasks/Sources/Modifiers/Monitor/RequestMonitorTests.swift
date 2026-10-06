//
// See LICENSE for this package's licensing information.
//

import Dispatch
import SwiftAsyncStream
import Testing

@testable import RequestDL
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
import struct Foundation.UUID
import struct Foundation.URL
import class Foundation.JSONEncoder
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
    private var _transactions: [RequestMetrics.Transaction] = []
    private var _timeline: [String] = []
    private let createdAt = DispatchTime.now().uptimeNanoseconds

    /// Microseconds each progress call takes, to model a monitor slower than the network.
    let progressDelay: UInt32

    init(progressDelay: UInt32 = 0) {
        self.progressDelay = progressDelay
    }

    /// Blocks the calling thread, the way a monitor doing slow work would. Through `Dispatch`
    /// rather than a libc call, which is spelled differently on every platform this builds for.
    private func block(for microseconds: UInt32) {
        guard microseconds > 0 else {
            return
        }

        _ = DispatchSemaphore(value: 0).wait(timeout: .now() + .microseconds(Int(microseconds)))
    }

    var uploads: [Transfer] { lock.withLock { _uploads } }
    var downloads: [Transfer] { lock.withLock { _downloads } }
    var executions: [RequestExecution] { lock.withLock { _states.map(\.execution) } }
    var transactions: [RequestMetrics.Transaction] { lock.withLock { _transactions } }

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
        block(for: progressDelay)

        lock.withLock {
            _uploads.append(.init(execution: execution.id, bytes: bytes, total: total, expected: expected))
        }
    }

    func request(_ execution: RequestExecution, didDownload bytes: Int, total: Int, of expected: Int?) {
        block(for: progressDelay)

        lock.withLock {
            _downloads.append(.init(execution: execution.id, bytes: bytes, total: total, expected: expected))
        }
    }

    /// Each state change with how long after this monitor was created it was heard, to say what
    /// happened when a test that waits for the end of a request doesn't see one.
    var timeline: [String] { lock.withLock { _timeline } }

    func request(_ execution: RequestExecution, didChange state: RequestState) {
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - createdAt) / 1_000_000_000

        lock.withLock {
            _states.append((execution, state))
            _timeline.append("\(Self.name(state)) +\(elapsed)s")
        }
    }

    func request(_ execution: RequestExecution, didCollect transaction: RequestMetrics.Transaction) {
        lock.withLock { _transactions.append(transaction) }
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

    /// A hook that fails before the request is sent is a failed request all the same: the monitor
    /// hears it started and hears it failed, like any other.
    @Test
    func aRequestThatFailsBeforeItsExecutorIsChosen_isReportedAsStartedThenFailed() async throws {
        // Given
        struct Failing: TaskDescriptor {
            struct Failure: Error {}

            func describe(_ context: TaskDescriptorContext) async throws -> Bool {
                throw Failure()
            }
        }

        let monitor = RecordingMonitor()

        // When
        await #expect(throws: Failing.Failure.self) {
            _ = try await DataTask {
                BaseURL("example.com")
            }
            .description(Failing()) { _ in }
            .monitor(monitor)
            .result()
        }

        try await eventually(timeout: 120) { monitor.hasEnded }

        // Then
        #expect(monitor.states() == ["started", "failed"])
        #expect(monitor.failure is Failing.Failure)
    }

    /// The same for a budget that runs out before there is a client to send it with, which is where
    /// a request that is too slow to even start ends.
    @Test
    func aRequestWhoseBudgetRunsOutBeforeItIsSent_isReportedAsStartedThenFailed() async throws {
        // Given
        struct Stalling: TaskDescriptor {
            func describe(_ context: TaskDescriptorContext) async throws -> Bool {
                try await _Concurrency.Task.sleep(nanoseconds: 30_000_000_000)
                return true
            }
        }

        let monitor = RecordingMonitor()

        // When
        await #expect(throws: ResourceTimeoutError.self) {
            _ = try await DataTask {
                BaseURL("example.com")
                Timeout(.milliseconds(200), for: .resource)
            }
            .description(Stalling()) { _ in }
            .monitor(monitor)
            .result()
        }

        try await eventually(timeout: 120) { monitor.hasEnded }

        // Then
        #expect(monitor.states() == ["started", "failed"])
        #expect(monitor.failure is ResourceTimeoutError)
    }

    // MARK: - Metrics

    @Test(arguments: Executor.allCases)
    private func aRequest_reportsTheTransactionItRanAs(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given
            let monitor = RecordingMonitor()

            // When
            _ = try await Self.data(from: server, executor: executor)
                .monitor(monitor)
                .result()

            // Then: when the transport reports it is up to the transport, so this waits for it.
            try await eventually(timeout: 30) { monitor.transactions.count == 1 }

            let transaction = try #require(monitor.transactions.first)
            #expect(transaction.responseStart != nil)
            #expect(transaction.responseEnd != nil)
            #expect(transaction.connection != nil)
            #expect(transaction.error == nil)
        }
    }

    @Test(arguments: Executor.allCases)
    private func aRequestThatFails_stillReportsTheTransactionItRanAs(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: Self.length)) { server in
            // Given: the connection is cut after part of the body, so there is a response head and no end.
            server.dropPlan = [1_000_000]
            let monitor = RecordingMonitor()

            // When
            await #expect(throws: (any Error).self) {
                _ = try await Self.data(from: server, executor: executor)
                    .monitor(monitor)
                    .result()
            }

            // Then: the request threw, so there is no `TaskResult` to read the metrics from.
            try await eventually(timeout: 30) { monitor.hasEnded && monitor.transactions.count == 1 }

            let transaction = try #require(monitor.transactions.first)
            #expect(transaction.responseStart != nil)
            #expect(transaction.responseEnd == nil)
            #expect(monitor.failure != nil)
        }
    }

    #if canImport(NIOCore)
    /// Without `URLSession`. A refused connection to a closed port is a scenario `URLSession` has taken
    /// minutes to settle on CI runners, well past the 3 s budget below (the test that follows hits the
    /// same wait, and it fails there too). What this one adds, a transaction without a response, is
    /// already covered for `URLSession` by the download that is cut mid-body above.
    private static var executorsThatSettleARefusedConnection: [Executor] {
        Executor.allCases.filter { $0.testDescription != "urlSession" }
    }

    @Test(arguments: executorsThatSettleARefusedConnection)
    private func aRequestThatNeverGetsSent_reportsATransactionWithoutAResponse(_ executor: Executor) async throws {
        // Given: nothing listens on this port.
        let monitor = RecordingMonitor()

        // When
        await #expect(throws: (any Error).self) {
            _ = try await DataTask {
                BaseURL(.http, host: "127.0.0.1:1")
                Path("/resource")
                executor.session
                Timeout(.seconds(3), for: .resource)
            }
            .monitor(monitor)
            .result()
        }

        // Then: generous for the same reason as the test below.
        try await eventually(timeout: 120) { !monitor.transactions.isEmpty }

        let transaction = try #require(monitor.transactions.first)
        #expect(transaction.responseStart == nil)
    }
    #endif

    @Test(arguments: Executor.allCases)
    private func aRequestThatNeverGetsSent_isReportedAsStartedThenFailed(_ executor: Executor) async throws {
        // Given: a port nothing listens on any more. One a server held a moment ago, so that the
        // connection is refused, and not a well-known one (`1` is `tcpmux`), whose treatment is up
        // to whatever machine runs this.
        let port = try await withTransferServer(.init(length: 1)) { $0.port }
        let monitor = RecordingMonitor()
        let start = DispatchTime.now().uptimeNanoseconds

        // When: the request is bounded by a 3s budget, and so is this wait for it. A transport that
        // doesn't honour the budget fails the test here, saying what it did, instead of holding
        // every other test of the run back for as long as it takes to give up on its own.
        let outcome = await withTaskGroup(of: String.self) { group in
            group.addTask {
                do {
                    _ = try await DataTask {
                        BaseURL(.http, host: "127.0.0.1:\(port)")
                        Path("/resource")
                        executor.session

                        // Some transports keep retrying a refused connection for a while; the
                        // request is failing either way, and this only keeps the test from
                        // waiting on them.
                        Timeout(.seconds(3), for: .resource)
                    }
                    .monitor(monitor)
                    .result()

                    return "succeeded"
                } catch {
                    return "failed: \(error)"
                }
            }

            group.addTask {
                try? await _Concurrency.Task.sleep(nanoseconds: 90_000_000_000)
                return "still running after 90s"
            }

            defer { group.cancelAll() }
            return await group.next() ?? "nothing"
        }

        let requestElapsed = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000_000

        // The end of the request is reported after the request itself fails.
        for _ in 0..<300 where !monitor.hasEnded {
            try await _Concurrency.Task.sleep(nanoseconds: 100_000_000)
        }

        // Then
        let report = "\(executor.testDescription): the request \(outcome) after \(requestElapsed)s; \(monitor.timeline)"

        #expect(outcome.hasPrefix("failed"), Comment(rawValue: report))
        #expect(monitor.states() == ["started", "failed"], Comment(rawValue: report))
    }

    // MARK: - Defaults, rejection and the cache

    /// A monitor implements only what it needs: one that implements nothing is told about a request
    /// all the same, through the empty defaults, and the request is unaffected.
    @Test(arguments: Executor.allCases)
    private func aMonitorThatImplementsNothing_changesNothing(_ executor: Executor) async throws {
        struct Silent: RequestMonitor {}

        try await withTransferServer(.init(length: 1_024)) { server in
            // When: an upload, so that every kind of event is produced.
            let data = try await UploadTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Path("/upload")
                RequestMethod(.put)
                executor.session
                Payload(data: Data(repeating: 7, count: 256 * 1_024))
            }
            .collectData()
            .extractPayload()
            .monitor(Silent())
            .result()

            // Then
            #expect(!data.isEmpty)

            try await eventually(timeout: 30) { !server.requests.isEmpty }
            #expect(server.requests.first?.bodyLength == 256 * 1_024)
        }
    }

    /// A request rejected before it is ever sent still ends: started, then failed, and nothing
    /// reaches the network.
    @Test(arguments: Executor.allCases)
    private func aRequestRejectedBeforeBeingSent_isReportedAsStartedThenFailed(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: 1_024)) { server in
            // Given: a body to compress, and a `Content-Encoding` already set, which is a conflict
            // that is refused before anything is sent.
            let monitor = RecordingMonitor()

            // When
            await #expect(throws: (any Error).self) {
                _ = try await UploadTask {
                    BaseURL(.http, host: "127.0.0.1:\(server.port)")
                    Path("/upload")
                    RequestMethod(.put)
                    executor.session
                    CustomHeader(name: "Content-Encoding", value: "br")
                    Payload(data: Data(repeating: 7, count: 64 * 1_024))
                        .compression(.gzip)
                }
                .collectData()
                .extractPayload()
                .monitor(monitor)
                .result()
            }

            try await eventually(timeout: 30) { monitor.hasEnded }

            // Then
            #expect(monitor.states() == ["started", "failed"])
            #expect(monitor.failure != nil)
            #expect(server.acceptedConnections == 0)
        }
    }

    /// A response served from the cache never reaches an executor, which is where an execution
    /// otherwise ends: it finishes right after it starts, having moved nothing on the network.
    @Test
    private func aResponseServedFromTheCache_finishesRightAfterItStarts() async throws {
        let certificate = Certificates().server()
        let uniqueKey = UUID().uuidString
        let uri = "/" + uniqueKey
        let dataCache = DataCache(suiteName: uniqueKey)
        let localServer = try await LocalServer(.standard)

        localServer.cleanup(at: uri)
        await dataCache.removeAll()
        dataCache.memoryCapacity = 8 * 1_024 * 1_024

        let body = try JSONEncoder().encode("from the cache")

        await dataCache.setCachedData(
            await CachedData(
                response: ResponseHead(
                    url: URL(string: "https://localhost:8888"),
                    status: .init(code: 200, reason: "Ok"),
                    version: .init(minor: 1, major: 2),
                    headers: HTTPHeaders([
                        ("Cache-Control", "public, max-age=3600"),
                        ("Content-Length", String(body.count)),
                    ]),
                    isKeepAlive: false
                ),
                policy: .all,
                data: body
            ),
            forKey: "https://localhost:8888" + uri
        )

        let monitor = RecordingMonitor()

        // When
        let data = try await DataTask {
            Session.localServer
                .cachePolicy(.all)
                .cacheStrategy(.returnCachedDataElseLoad)
                .cache(memoryCapacity: .zero, diskCapacity: .zero, url: dataCache.directoryURL, encryptionKey: nil)

            SecureConnection {
                TrustRoots(certificate.certificateURL.absolutePath(percentEncoded: false))
            }

            BaseURL(localServer.baseURL)
            Path(uri)
        }
        .extractPayload()
        .monitor(monitor)
        .result()

        try await eventually(timeout: 30) { monitor.hasEnded }

        // Then: the cached body, and an execution that started and finished without a byte moved.
        #expect(data == body)
        #expect(monitor.states() == ["started", "finished"])
        #expect(monitor.downloads.isEmpty)
        #expect(monitor.uploads.isEmpty)

        localServer.cleanup(at: uri)
        await dataCache.removeAll()
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
