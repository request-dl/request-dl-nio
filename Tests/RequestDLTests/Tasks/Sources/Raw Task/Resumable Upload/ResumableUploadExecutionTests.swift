//
// See LICENSE for this package's licensing information.
//

import Testing

@_spi(Private) @testable import RequestDL
@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// A resumable upload through the whole stack, against a real socket server that speaks the
/// protocol, on every executor available and for every dialect.
@Suite(.serialized, .concurrent(watchdogAffectedPlatformConcurrencyLimit), .nonFatalWatchdog)
struct ResumableUploadExecutionTests {

    // MARK: - Private types

    private typealias Executor = TransferTestExecutor
    private typealias Kind = ResumableUploadDialectKind

    private struct Case: Sendable, CustomTestStringConvertible {
        let executor: Executor
        let kind: Kind

        var testDescription: String {
            "\(executor.testDescription), \(kind.testDescription)"
        }
    }

    private static let size = 300 * 1_024

    private static var cases: [Case] {
        Executor.allCases.flatMap { executor in
            Kind.allCases.map { Case(executor: executor, kind: $0) }
        }
    }

    // MARK: - The whole upload

    @Test(arguments: cases)
    private func anUpload_isCreatedThenSentWhole(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // When
            let result = try await Self.upload(to: server, scenario).result()

            // Then: the body is all there, in order, and the response is the protocol's.
            #expect(server.heldUploads[1]?.data == Self.body())
            #expect(server.heldUploads[1]?.isComplete == true)

            switch scenario.kind {
            case .ietf:
                #expect(result.head.status.code == 200)
                #expect(result.head.headers.first(name: "X-Upload") == "done")
                #expect(String(decoding: result.payload, as: UTF8.self) == "done")
            case .tus:
                #expect(result.head.status.code == 204)
            }

            // Then: what went over the wire.
            let requests = server.requests
            #expect(requests.map(\.method) == [scenario.kind == .ietf ? "PUT" : "POST", "PATCH"])
            #expect(requests.last?.path == "/uploads/1")
            #expect(requests.last?.header("Upload-Offset") == "0")
            #expect(requests.last?.bodyLength == Self.size)
        }
    }

    @Test(arguments: cases)
    private func aConnectionLostMidBody_isContinuedFromTheOffsetTheServerHolds(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given: the first `PATCH` is cut after 100,000 bytes.
            server.uploadDropPlan = [100_000]

            // When
            let result = try await Self.upload(to: server, scenario).result()

            // Then
            #expect([200, 204].contains(result.head.status.code))
            #expect(server.heldUploads[1]?.data == Self.body())

            let requests = server.requests
            #expect(requests.map(\.method).suffix(3) == ["PATCH", "HEAD", "PATCH"])
            #expect(requests.last?.header("Upload-Offset") == "100000")
            #expect(requests.last?.bodyLength == Self.size - 100_000)
        }
    }

    @Test(arguments: cases)
    private func severalLosses_areEachContinuedFromWhereTheServerStands(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given: cut after 50,000 bytes, then 70,000 bytes into what remains.
            server.uploadDropPlan = [50_000, 70_000]

            // When
            _ = try await Self.upload(to: server, scenario).result()

            // Then
            #expect(server.heldUploads[1]?.data == Self.body())
            #expect(
                server.requests.filter { $0.method == "PATCH" }.map { $0.header("Upload-Offset") } == [
                    "0", "50000", "120000",
                ]
            )
        }
    }

    // MARK: - What the server disagrees about

    @Test(arguments: cases)
    private func anOffsetTheServerDoesNotHold_isReplacedByTheServers(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given: cut after 100,000 bytes, and the server then loses the last 40,000 of them,
            // so what the client is told it holds is not what it holds by the time it sends.
            server.uploadDropPlan = [100_000]
            server.forgetsBytesBeforeNextPatch = 40_000

            // When
            _ = try await Self.upload(to: server, scenario).result()

            // Then: the conflict is answered with where the server really is.
            #expect(server.heldUploads[1]?.data == Self.body())
            #expect(
                server.requests.filter { $0.method == "PATCH" }.map { $0.header("Upload-Offset") }
                    == ["0", "100000", "60000"]
            )
        }
    }

    @Test(arguments: cases)
    private func anUploadTheServerNoLongerHas_failsWithoutSendingItAgain(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given
            server.expiresUploadsBeforeNextRequest = true

            // Then
            await #expect(throws: UploadResumptionError(.uploadLost(status: 404))) {
                _ = try await Self.upload(to: server, scenario).result()
            }

            #expect(server.requests.filter { $0.method == "PATCH" }.count == 1)
        }
    }

    @Test(arguments: Executor.allCases)
    private func aServerThatKeepsOnlyPartOfTheBody_isSentTheRestAgain(_ executor: Executor) async throws {
        let scenario = Case(executor: executor, kind: .tus)

        try await Self.withUploadServer(scenario) { server in
            // Given: each `PATCH` is answered with an offset short of the length.
            server.keepsAtMostPerPatch = 100_000

            // When
            _ = try await Self.upload(to: server, scenario).result()

            // Then: the body is sent in pieces, each from where the server says it is.
            #expect(server.heldUploads[1]?.data == Self.body())
            #expect(
                server.requests.filter { $0.method == "PATCH" }.map { $0.header("Upload-Offset") }
                    == ["0", "100000", "200000", "300000"]
            )
        }
    }

    @Test(arguments: cases)
    private func aServerThatKeepsAnsweringNotNow_isAskedAgainUntilItAnswers(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given: the connection is lost, and the server then says "not now" twice.
            server.uploadDropPlan = [100_000]
            server.headStatuses = [503, 429]

            // When
            _ = try await Self.upload(to: server, scenario).result()

            // Then
            #expect(server.heldUploads[1]?.data == Self.body())
            #expect(server.requests.filter { $0.method == "HEAD" }.map(\.status) == [503, 429, 204])
        }
    }

    @Test(arguments: cases)
    private func aServerThatNeverAnswersTheOffsetQuery_endsInTheFailureOfTheLastAttempt(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given
            server.uploadDropPlan = [100_000]
            server.headStatuses = Array(repeating: 503, count: 10)

            // Then: the budget runs out, and what ends it is the answer of the server.
            await #expect(throws: UploadResumptionError(.serverUnavailable(status: 503))) {
                _ = try await Self.upload(to: server, scenario, attempts: 2).result()
            }

            #expect(server.requests.filter { $0.method == "HEAD" }.count == 2)
        }
    }

    @Test(arguments: cases)
    private func aServerThatDoesNotSayWhereItStands_isAnError(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given
            server.uploadDropPlan = [100_000]
            server.headOmitsOffset = true

            // Then
            await #expect(throws: UploadResumptionError(.offsetRejected(status: 204))) {
                _ = try await Self.upload(to: server, scenario).result()
            }
        }
    }

    @Test(arguments: cases)
    private func aServerThatHoldsMoreThanTheBody_isAnError(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given
            server.uploadDropPlan = [100_000]
            server.headOverstatesOffsetBy = Self.size

            // Then
            await #expect(throws: UploadResumptionError.self) {
                _ = try await Self.upload(to: server, scenario).result()
            }
        }
    }

    /// A `2xx` that holds no more than what was already known is an attempt that moved nothing,
    /// so it spends the retry budget instead of being sent again for as long as the server
    /// keeps answering it.
    @Test(arguments: Executor.allCases)
    private func aServerThatKeepsNothingOfTheBody_isGivenUpOn(_ executor: Executor) async throws {
        let scenario = Case(executor: executor, kind: .tus)

        try await Self.withUploadServer(scenario) { server in
            // Given: each `PATCH` is answered with an offset where the upload already was.
            server.keepsAtMostPerPatch = 0

            // Then
            await #expect(throws: UploadResumptionError(.conflictingOffsets)) {
                _ = try await Self.upload(to: server, scenario, attempts: 2).result()
            }

            // The first, and the two that follow it, which is what was allowed. The server records
            // a request once it is done with it, which can be after the client has failed, so
            // the list is waited on before it is counted.
            try await eventually(timeout: 30) { server.requests.filter { $0.method == "PATCH" }.count >= 3 }
            #expect(server.requests.filter { $0.method == "PATCH" }.count == 3)
        }
    }

    @Test(arguments: cases)
    private func aServerThatKeepsRejectingTheOffset_isGivenUpOn(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given
            server.rejectsEveryPatchWithConflict = true

            // Then
            await #expect(throws: UploadResumptionError(.conflictingOffsets)) {
                _ = try await Self.upload(to: server, scenario, attempts: 2).result()
            }

            // The first, and the two that follow it, which is what was allowed.
            #expect(server.requests.filter { $0.method == "PATCH" }.count == 3)
        }
    }

    @Test(arguments: cases)
    private func anUploadThatIsGoneWhenTheServerIsAsked_failsWithoutSendingItAgain(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given: the connection is lost, and the server no longer has the upload by the time it
            // is asked where it stands.
            server.uploadDropPlan = [100_000]
            server.headStatuses = [404]

            // Then
            await #expect(throws: UploadResumptionError(.uploadLost(status: 404))) {
                _ = try await Self.upload(to: server, scenario).result()
            }

            #expect(server.requests.filter { $0.method == "PATCH" }.count == 1)
        }
    }

    // MARK: - Giving up

    @Test(arguments: cases)
    private func attemptsThatMoveNothing_areGivenUpOn(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given: every `PATCH` is cut before a byte reaches the server.
            server.uploadDropPlan = Array(repeating: 0, count: 20)

            // When
            await #expect(throws: (any Error).self) {
                _ = try await Self.upload(to: server, scenario, attempts: 2).result()
            }

            // Then: the first, and the two that follow it, which is what was allowed.
            #expect(server.requests.filter { $0.method == "PATCH" }.count == 3)
            #expect(server.heldUploads[1]?.data.isEmpty == true)
        }
    }

    // MARK: - What the server answers to the creation

    @Test(arguments: cases)
    private func aCreationThatIsRefused_isTheResponseOfTheUpload(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given
            server.creationStatus = 401

            // When
            let result = try await Self.upload(to: server, scenario).result()

            // Then: what the server has to say about the request that was written, as usual.
            #expect(result.head.status.code == 401)
            #expect(server.requests.count == 1)
        }
    }

    @Test(arguments: cases)
    private func aServerThatDoesNotSayWhereTheUploadIs_isNotSupported(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given
            server.omitsLocationOnCreation = true

            // Then
            await #expect(throws: UploadResumptionError(.notSupported)) {
                _ = try await Self.upload(to: server, scenario).result()
            }
        }
    }

    @Test(arguments: cases)
    private func aResponseLostAfterTheUploadWasCompleted_isRecoveredOnlyWhereTheProtocolAllows(
        _ scenario: Case
    ) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given: the server has the whole body and never answers.
            server.dropsFinalResponse = true

            switch scenario.kind {
            case .ietf:
                // The response is the application's, and nothing else says what it was.
                await #expect(throws: UploadResumptionError(.completedWithoutResponse)) {
                    _ = try await Self.upload(to: server, scenario).result()
                }
            case .tus:
                // What tus answers carries nothing but the offset, which asking for it says too.
                let result = try await Self.upload(to: server, scenario).result()
                #expect(result.head.status.code == 204)
            }

            #expect(server.heldUploads[1]?.data == Self.body())
            #expect(server.requests.filter { $0.method == "PATCH" }.count == 1)
        }
    }

    // MARK: - Compression

    @Test(arguments: cases)
    private func aCompressedBody_isSentAsTheBytesThatWereCompressedOnce(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given: a body that compresses, so its length on the wire is not the one it was
            // written with.
            let payload = Data(String(repeating: "resumable ", count: 30_000).utf8)
            server.uploadDropPlan = [200]

            // When
            _ = try await Self.upload(to: server, scenario, payload: payload, compressed: true).result()

            // Then: the server holds exactly what a compression of the payload produces, however
            // many times the upload was continued.
            let expected = try await Self.compressed(payload)
            #expect(server.heldUploads[1]?.data == Array(expected))
            #expect(expected.count < payload.count)

            let requests = server.requests

            switch scenario.kind {
            case .ietf:
                // The request that creates the upload is the one that was written.
                #expect(requests.first?.header("Content-Encoding") == "gzip")
            case .tus:
                // tus declares the length of what goes on the wire, and has nowhere to say how it
                // is encoded.
                #expect(requests.first?.header("Upload-Length") == String(expected.count))
            }

            #expect(requests.filter { $0.method == "PATCH" }.allSatisfy { $0.header("Content-Encoding") == nil })
        }
    }

    // MARK: - Observing and controlling

    @Test(arguments: cases)
    private func aMonitor_seesOneExecution_andEveryByteThatCrossedTheNetwork(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given: a loss, and then a disagreement about where to continue from, so part of the
            // body crosses the network more than once.
            server.uploadDropPlan = [100_000]
            server.forgetsBytesBeforeNextPatch = 40_000

            let monitor = RecordingMonitor()

            // When
            _ = try await Self.upload(to: server, scenario).monitor(monitor).result()
            try await eventually(timeout: 120) { monitor.hasEnded }

            // Then: one execution, started once and finished once, with the retries in between.
            #expect(monitor.states().first == "started")
            #expect(monitor.states().last == "finished")
            #expect(monitor.states().filter { $0.hasPrefix("reconnecting") }.first == "reconnecting(1)")
            #expect(monitor.states().filter { $0 == "finished" || $0 == "failed" }.count == 1)
            #expect(Set(monitor.executions.map(\.id)).count == 1)

            // Then: what is counted is what was sent, not what the body is: more than the body.
            let uploads = monitor.uploads
            #expect(uploads.allSatisfy { $0.expected == Self.size })
            #expect(try #require(uploads.last).total > Self.size)
            #expect(uploads.map(\.bytes).reduce(0, +) == uploads.last?.total)

            // Then: only the response of the upload is counted as received.
            if scenario.kind == .ietf {
                #expect(monitor.downloads.last?.total == 4)
            } else {
                #expect(monitor.downloads.isEmpty)
            }
        }
    }

    @Test(arguments: Executor.allCases, Kind.allCases)
    private func suspendMidUpload_stopsTheBodyUntilResumed(_ executor: Executor, _ kind: Kind) async throws {
        let scenario = Case(executor: executor, kind: kind)
        let size = 6 * 1_048_576

        try await Self.withUploadServer(scenario) { server in
            // Given
            let controller = RequestController()
            let suspendedAt = LockedValueBox<Int?>(nil)

            server.uploadReadDelay = 2_000
            server.onUploadProgress = { received in
                guard received >= 262_144, suspendedAt.withLockedValue({ $0 == nil }) else {
                    return
                }

                suspendedAt.withLockedValue { $0 = received }
                controller.suspend()
            }

            let running = _Concurrency.Task {
                try await Self.upload(to: server, scenario, payload: Data(Self.body(size: size)))
                    .controller(controller)
                    .result()
            }

            try await eventually(timeout: 120) { suspendedAt.withLockedValue { $0 != nil } }
            server.onUploadProgress = nil

            let stalledAt = try await server.settled { server.uploadBytesReceived }

            // Then: what was already in the socket buffers still arrives, and nothing more.
            #expect(stalledAt < size)

            try await _Concurrency.Task.sleep(nanoseconds: 700_000_000)
            #expect(server.uploadBytesReceived == stalledAt)

            // When
            controller.resume()
            _ = try await running.value

            // Then
            #expect(server.heldUploads[1]?.data == Self.body(size: size))
        }
    }

    @Test(arguments: cases)
    private func aSuspensionAfterALoss_holdsTheNextAttemptUntilResumed(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given: the connection is lost, and the application suspends the request as soon as it
            // hears it is going to try again, which it has time to do before the attempt is made.
            server.uploadDropPlan = [100_000]

            let controller = RequestController()
            let monitor = SuspendingMonitor { state in
                if case .reconnecting = state {
                    controller.suspend()
                }
            }

            let running = _Concurrency.Task {
                try await Self.upload(to: server, scenario, delay: 0.4)
                    .monitor(monitor)
                    .controller(controller)
                    .result()
            }

            try await eventually(timeout: 120) { controller.isSuspended }
            try await _Concurrency.Task.sleep(nanoseconds: 900_000_000)

            // Then: no attempt to find out where the upload stands, nor to send the rest.
            #expect(server.requests.map(\.method).suffix(1) == ["PATCH"])

            // When
            controller.resume()
            _ = try await running.value

            // Then
            #expect(server.heldUploads[1]?.data == Self.body())
        }
    }

    @Test(arguments: cases)
    private func cancelling_stopsSendingAndDoesNotTryAgain(_ scenario: Case) async throws {
        let size = 6 * 1_048_576

        try await Self.withUploadServer(scenario) { server in
            // Given
            server.uploadReadDelay = 2_000

            let running = _Concurrency.Task {
                try await Self.upload(to: server, scenario, payload: Data(Self.body(size: size))).result()
            }

            try await eventually(timeout: 120) { server.uploadBytesReceived >= 100_000 }

            // When
            running.cancel()

            // Then
            await #expect(throws: (any Error).self) {
                _ = try await running.value
            }

            let settled = try await server.settled { server.uploadBytesReceived }
            #expect(settled < size)

            try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)
            #expect(server.requests.filter { $0.method == "PATCH" }.count == 1)
            #expect(server.requests.filter { $0.method == "HEAD" }.isEmpty)
        }
    }

    // MARK: - Cancelling, and what the server is told

    @Test(arguments: cases)
    private func cancelling_tellsTheServerTheUploadIsAbandoned(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given
            server.uploadReadDelay = 2_000

            let running = _Concurrency.Task {
                try await Self.upload(to: server, scenario, payload: Data(Self.body(size: 6 * 1_048_576))).result()
            }

            try await eventually { server.uploadBytesReceived >= 100_000 }

            // When
            running.cancel()
            _ = try? await running.value

            // Then: it is told, and what it held of the upload is gone.
            try await eventually { server.requests.contains { $0.method == "DELETE" } }
            #expect(server.requests.filter { $0.method == "DELETE" }.count == 1)
            #expect(server.requests.filter { $0.method == "DELETE" }.first?.path == "/uploads/1")
            #expect(server.heldUploads[1] == nil)
        }
    }

    @Test(arguments: cases)
    private func cancelling_whenAskedToKeepTheUpload_leavesItOnTheServer(_ scenario: Case) async throws {
        try await Self.withUploadServer(scenario) { server in
            // Given
            server.uploadReadDelay = 2_000

            let running = _Concurrency.Task {
                try await Self.upload(
                    to: server,
                    scenario,
                    cancellation: .keepOnServer,
                    payload: Data(Self.body(size: 6 * 1_048_576))
                )
                .result()
            }

            try await eventually { server.uploadBytesReceived >= 100_000 }

            // When
            running.cancel()
            _ = try? await running.value
            _ = try await server.settled { server.uploadBytesReceived }
            try await _Concurrency.Task.sleep(nanoseconds: 700_000_000)

            // Then
            #expect(server.requests.filter { $0.method == "DELETE" }.isEmpty)
            #expect(server.heldUploads[1] != nil)
        }
    }

    // MARK: - Not an upload

    @Test(arguments: Executor.allCases)
    private func aRequestWithNoBody_isNotAnUpload(_ executor: Executor) async throws {
        try await withTransferServer(.init(length: 4_096)) { server in
            // When
            let result = try await DataTask {
                BaseURL(.http, host: "127.0.0.1:\(server.port)")
                Path("/resource")
                executor.session
            }
            .resumingUploads(.ietf)
            .result()

            // Then
            #expect(result.head.status.code == 200)
            #expect(result.payload.count == 4_096)
            #expect(server.requests.map(\.method) == ["GET"])
        }
    }

    // MARK: - Helpers

    private static func body(size: Int = size) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(size)

        var position = 0
        while position < size {
            let count = min(TransferServer.maximumPiece, size - position)
            bytes.append(contentsOf: TransferServer.uploadBody(from: position, count: count))
            position += count
        }

        return bytes
    }

    private static func withUploadServer(
        _ scenario: Case,
        perform body: (TransferServer) async throws -> Void
    ) async throws {
        try await withTransferServer(.init(length: 1_024)) { server in
            server.resumableProtocol = scenario.kind == .ietf ? .ietf : .tus
            try await body(server)
        }
    }

    private static func upload(
        to server: TransferServer,
        _ scenario: Case,
        attempts: Int = 3,
        delay: Double = 0.01,
        cancellation: UploadCancellation = .terminate,
        payload: Data? = nil,
        compressed: Bool = false
    ) -> AnyTask<TaskResult<Data>> {
        let payload = payload ?? Data(body())

        let task = UploadTask {
            BaseURL(.http, host: "127.0.0.1:\(server.port)")
            Path("/files/report.bin")
            RequestMethod(.put)
            scenario.executor.session

            if compressed {
                Payload(data: payload)
                    .compression(.gzip)
            } else {
                Payload(data: payload)
            }
        }
        .collectData()

        switch scenario.kind {
        case .ietf:
            return task.resumingUploads(
                .ietf,
                maximumAttemptsWithoutProgress: attempts,
                delay: delay,
                onCancellation: cancellation
            )
        case .tus:
            return task.resumingUploads(
                .tus,
                maximumAttemptsWithoutProgress: attempts,
                delay: delay,
                onCancellation: cancellation
            )
        }
    }

    private static func compressed(_ payload: Data) async throws -> Data {
        var configuration = RequestConfiguration()
        configuration.compression = InternalsCompressionAlgorithmAdapter(algorithm: GzipAlgorithm())
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(payload)])

        try configuration.applyCompression()

        return try await #require(configuration.body).data()
    }
}

/// A monitor that runs a closure for every state change.
private struct SuspendingMonitor: RequestMonitor {

    let onState: @Sendable (RequestState) -> Void

    init(_ onState: @escaping @Sendable (RequestState) -> Void) {
        self.onState = onState
    }

    func request(_ execution: RequestExecution, didChange state: RequestState) {
        onState(state)
    }
}
