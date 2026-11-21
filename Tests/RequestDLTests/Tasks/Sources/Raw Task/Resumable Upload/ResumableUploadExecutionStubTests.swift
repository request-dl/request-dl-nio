//
// See LICENSE for this package's licensing information.
//

import SwiftAsyncStream
import Testing

@_spi(Private) @testable import RequestDL
@testable import RequestDLInternals
@testable import RequestDLTestSupport

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import struct Foundation.Data
#endif

/// The execution of a resumable upload against a client that does what the test says, for what no
/// server can be made to do: an executor that fails to start a request, a cancellation that lands
/// at an exact point, a response body that breaks after its head.
struct ResumableUploadExecutionStubTests {

    // MARK: - Private types

    private struct StubError: Error, Equatable {}

    private struct ScriptedClient: RequestExecutingClient {

        let script: @Sendable (RequestConfiguration) async throws -> SessionTask

        func execute(
            configuration: RequestConfiguration,
            decompression: Internals.Decompression,
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.Chunk>?)?,
            logger: Internals.TaskLogger?,
            transferControl: Internals.TransferControl?
        ) async throws -> SessionTask {
            try await script(configuration)
        }

        func revalidationHead(
            configuration: RequestConfiguration,
            logger: Internals.TaskLogger?,
            metrics: Internals.RequestMetricsCollector?
        ) async throws -> Internals.ResponseHead {
            ResumableUploadExecutionStubTests.head(status: 304)
        }
    }

    // MARK: - Failing to start

    @Test
    func anExecutorThatFailsToStartARequest_failsTheUpload() async throws {
        // Given
        let execution = try await Self.execution(client: ScriptedClient { _ in throw StubError() })

        // When
        execution.start()

        // Then
        await #expect(throws: StubError.self) {
            for try await _ in execution.response {}
        }
    }

    // MARK: - Cancelling

    @Test
    func cancellingBeforeItStarts_sendsNothing() async throws {
        // Given
        let started = LockedValueBox(false)
        let execution = try await Self.execution(
            client: ScriptedClient { _ in
                started.withLockedValue { $0 = true }
                throw StubError()
            }
        )

        // When
        execution.makeSeed()()
        execution.start()

        // Then
        await #expect(throws: CancellationError.self) {
            for try await _ in execution.response {}
        }

        #expect(!started.withLockedValue { $0 })
    }

    @Test
    func droppingTheSeed_cancelsTheUpload() async throws {
        // Given
        let started = LockedValueBox(false)
        let execution = try await Self.execution(
            client: ScriptedClient { _ in
                started.withLockedValue { $0 = true }
                throw StubError()
            }
        )

        // When: whoever held the response lets go of it.
        var seed: Internals.TaskSeed? = execution.makeSeed()
        seed = nil
        _ = seed

        execution.start()

        // Then
        await #expect(throws: CancellationError.self) {
            for try await _ in execution.response {}
        }

        #expect(!started.withLockedValue { $0 })
    }

    @Test
    func cancellingWhileTheExecutorStartsARequest_cancelsThatRequest() async throws {
        // Given: an executor that takes its time, and a request that can be told it is cancelled.
        let entered = LockedValueBox(false)
        let cancelled = LockedValueBox(false)
        let gate = Gate()

        let execution = try await Self.execution(
            client: ScriptedClient { _ in
                entered.withLockedValue { $0 = true }
                await gate.wait()

                return await Self.sessionTask(
                    head: Self.head(status: 201, headers: [("Location", "/uploads/1")]),
                    seed: Internals.TaskSeed { cancelled.withLockedValue { $0 = true } }
                )
            }
        )

        execution.start()
        try await eventually { entered.withLockedValue { $0 } }

        // When
        execution.makeSeed()()
        gate.open()

        // Then
        await #expect(throws: (any Error).self) {
            for try await _ in execution.response {}
        }

        #expect(cancelled.withLockedValue { $0 })
    }

    // MARK: - Where the server puts the upload

    @Test(arguments: [false, true])
    func anUploadTheServerPutsOnAnotherOrigin_getsTheCredentialsOnlyWhenAskedTo(_ forwards: Bool) async throws {
        // Given: a creation answered with another origin, and a body that is being sent there.
        let sent = LockedValueBox<[String: String?]>([:])
        let gate = Gate()

        let execution = try await Self.execution(
            forwardsCredentialsToOtherOrigins: forwards,
            client: ScriptedClient { configuration in
                sent.withLockedValue {
                    $0[configuration.method ?? ""] = configuration.headers.first(name: "Authorization")
                }

                if configuration.method == "PATCH" {
                    await gate.wait()
                }

                return await Self.sessionTask(
                    head: Self.head(status: 201, headers: [("Location", "https://uploads.example.net/u/1")])
                )
            }
        )

        execution.start()
        try await eventually { sent.withLockedValue { $0 }.keys.contains("PATCH") }

        // When
        execution.makeSeed()()
        gate.open()

        // Then: the creation went to the server the caller named, so it always carries them.
        try await eventually { sent.withLockedValue { $0 }.keys.contains("DELETE") }

        let headers = sent.withLockedValue { $0 }
        let expected: String? = forwards ? "Bearer token" : nil

        #expect(headers["PUT"] == "Bearer token")
        #expect(headers["PATCH"] == expected)
        #expect(headers["DELETE"] == expected)
    }

    // MARK: - What the server is told when the upload is cancelled

    @Test
    func cancellingAnUploadThatWasCreated_terminatesIt() async throws {
        // Given: a creation that is answered, and a body that is being sent.
        let methods = LockedValueBox<[String]>([])
        let gate = Gate()

        let execution = try await Self.execution(
            client: ScriptedClient { configuration in
                methods.withLockedValue { $0.append(configuration.method ?? "") }

                if configuration.method == "PATCH" {
                    await gate.wait()
                }

                return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
            }
        )

        execution.start()
        try await eventually { methods.withLockedValue { $0 }.contains("PATCH") }

        // When
        execution.makeSeed()()
        gate.open()

        // Then: the server is told, with the upload's own URL.
        try await eventually { methods.withLockedValue { $0 }.contains("DELETE") }
        #expect(methods.withLockedValue { $0 } == ["PUT", "PATCH", "DELETE"])
    }

    @Test
    func aServerThatCannotBeToldTheUploadIsAbandoned_doesNotMatter() async throws {
        // Given: the executor fails to start the request that tells it.
        let methods = LockedValueBox<[String]>([])
        let gate = Gate()

        let execution = try await Self.execution(
            client: ScriptedClient { configuration in
                methods.withLockedValue { $0.append(configuration.method ?? "") }

                if configuration.method == "DELETE" {
                    throw StubError()
                }

                if configuration.method == "PATCH" {
                    await gate.wait()
                }

                return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
            }
        )

        execution.start()
        try await eventually { methods.withLockedValue { $0 }.contains("PATCH") }

        // When
        execution.makeSeed()()
        gate.open()

        // Then: it was tried, and that is all there is to it.
        try await eventually { methods.withLockedValue { $0 }.contains("DELETE") }
        await #expect(throws: (any Error).self) {
            for try await _ in execution.response {}
        }
    }

    @Test
    func aProtocolWithNoWayToAbandonAnUpload_isNeverTold() async throws {
        // Given
        let methods = LockedValueBox<[String]>([])
        let gate = Gate()

        let execution = try await Self.execution(
            dialect: NoCancellationDialect(),
            client: ScriptedClient { configuration in
                methods.withLockedValue { $0.append(configuration.method ?? "") }

                if configuration.method == "PATCH" {
                    await gate.wait()
                }

                return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
            }
        )

        execution.start()
        try await eventually { methods.withLockedValue { $0 }.contains("PATCH") }

        // When
        execution.makeSeed()()
        gate.open()
        try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)

        // Then
        #expect(methods.withLockedValue { $0 } == ["PUT", "PATCH"])
    }

    @Test
    func cancellingBeforeTheServerSaidWhereTheUploadIs_hasNothingToTerminate() async throws {
        // Given
        let methods = LockedValueBox<[String]>([])
        let gate = Gate()

        let execution = try await Self.execution(
            client: ScriptedClient { configuration in
                methods.withLockedValue { $0.append(configuration.method ?? "") }
                await gate.wait()
                return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
            }
        )

        execution.start()
        try await eventually { methods.withLockedValue { $0 }.contains("PUT") }

        // When
        execution.makeSeed()()
        gate.open()
        try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)

        // Then
        #expect(methods.withLockedValue { $0 } == ["PUT"])
    }

    @Test
    func cancellingAnUploadThatIsComplete_doesNotTerminateIt() async throws {
        // Given: the response of the upload has arrived, and its body has not ended.
        let methods = LockedValueBox<[String]>([])

        let execution = try await Self.execution(
            client: ScriptedClient { configuration in
                methods.withLockedValue { $0.append(configuration.method ?? "") }

                if configuration.method == "PATCH" {
                    return await Self.sessionTask(head: Self.head(status: 200), body: .endless)
                }

                return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
            }
        )

        execution.start()

        var iterator = execution.response.makeAsyncIterator()
        var step = try await iterator.next()

        while case .upload = step {
            step = try await iterator.next()
        }

        // When
        execution.makeSeed()()
        try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)

        // Then: there is nothing on the server to free, it has the whole of it.
        #expect(methods.withLockedValue { $0 } == ["PUT", "PATCH"])
    }

    @Test
    func cancellingWhenAskedToKeepTheUpload_doesNotTerminateIt() async throws {
        // Given
        let methods = LockedValueBox<[String]>([])
        let gate = Gate()

        let execution = try await Self.execution(
            cancellation: .keepOnServer,
            client: ScriptedClient { configuration in
                methods.withLockedValue { $0.append(configuration.method ?? "") }

                if configuration.method == "PATCH" {
                    await gate.wait()
                }

                return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
            }
        )

        execution.start()
        try await eventually { methods.withLockedValue { $0 }.contains("PATCH") }

        // When
        execution.makeSeed()()
        gate.open()
        try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)

        // Then
        #expect(methods.withLockedValue { $0 } == ["PUT", "PATCH"])
    }

    // MARK: - A server whose offset does not hold still

    /// Two replicas behind one balancer that hold 10 and 5 bytes, and answer in turn. The offset
    /// that is adopted moves forward and back, and what counts as progress is getting past the
    /// furthest the server was ever said to be, not past where it last said it was.
    @Test
    func aServerWhoseOffsetKeepsMovingBackAndForth_isGivenUpOn() async throws {
        // Given
        let patches = LockedValueBox(0)

        let execution = try await Self.execution(
            client: ScriptedClient { configuration in
                guard configuration.method == "PATCH" else {
                    return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
                }

                let count = patches.withLockedValue { value -> Int in
                    value += 1
                    return value
                }

                // A server that would be satisfied after enough of this, so that a client that
                // never gives up ends the test instead of hanging it.
                guard count <= 40 else {
                    return await Self.sessionTask(head: Self.head(status: 200))
                }

                return await Self.sessionTask(
                    head: Self.head(status: 409, headers: [("Upload-Offset", count.isMultiple(of: 2) ? "5" : "10")])
                )
            }
        )

        // When
        execution.start()

        // Then
        await #expect(throws: UploadResumptionError(.conflictingOffsets)) {
            for try await _ in execution.response {}
        }

        // The first, and the three that were allowed after it, give or take the one that moved forward.
        #expect(patches.withLockedValue { $0 } <= 6)
    }

    @Test
    func attemptsThatMoveNothingNew_waitBeforeTheNextOne() async throws {
        // Given: a server that disagrees, and says it holds nothing, every time. The wait is recorded
        // among the requests instead of being waited for, so what is asserted is the order of what
        // happened, and not how long it took.
        let events = LockedValueBox<[String]>([])

        let execution = try await Self.execution(
            delay: 7,
            sleep: { delay in events.withLockedValue { $0.append("wait \(delay)") } },
            client: ScriptedClient { configuration in
                guard configuration.method == "PATCH" else {
                    return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
                }

                events.withLockedValue { $0.append("PATCH") }
                return await Self.sessionTask(head: Self.head(status: 409, headers: [("Upload-Offset", "0")]))
            }
        )

        // When
        execution.start()

        await #expect(throws: UploadResumptionError(.conflictingOffsets)) {
            for try await _ in execution.response {}
        }

        // Then: each attempt after the first waited, instead of asking again right away, and the one
        // that ends it did not wait for a failure that was already decided.
        #expect(events.withLockedValue { $0 } == ["PATCH", "wait 7", "PATCH", "wait 7", "PATCH", "wait 7", "PATCH"])
    }

    @Test
    func aServerThatMovesForwardOnEveryConflict_isNotMadeToWaitBetweenThem() async throws {
        // Given: each `PATCH` is answered with a conflict that is further along than the last, which is
        // progress, and no reason to wait.
        let patches = LockedValueBox(0)
        let waits = LockedValueBox<[UInt64]>([])

        let execution = try await Self.execution(
            delay: 5_000_000_000,
            sleep: { delay in waits.withLockedValue { $0.append(delay) } },
            client: ScriptedClient { configuration in
                guard configuration.method == "PATCH" else {
                    return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
                }

                let count = patches.withLockedValue { value -> Int in
                    value += 1
                    return value
                }

                guard count < 5 else {
                    return await Self.sessionTask(head: Self.head(status: 200))
                }

                return await Self.sessionTask(
                    head: Self.head(status: 409, headers: [("Upload-Offset", String(count * 100))])
                )
            }
        )

        // When
        execution.start()
        for try await _ in execution.response {}

        // Then: it never waited.
        #expect(patches.withLockedValue { $0 } == 5)
        #expect(waits.withLockedValue { $0 }.isEmpty)
    }

    /// tus: the server keeps part of every `PATCH`, loses data once (it held 600, and says 100 when
    /// it is asked), and then climbs back 100 at a time. Every `PATCH` after the loss moved the
    /// upload forward, so none of them is a reason to give up, though none passes 600.
    @Test
    func aPartialAnswerThatMovesForwardAfterTheServerLostData_isProgress() async throws {
        let patches = LockedValueBox(0)

        let execution = try await Self.execution(
            dialect: TUSResumableUploadDialect(),
            client: ScriptedClient { configuration in
                switch configuration.method {
                case "POST":
                    return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
                case "HEAD":
                    return await Self.sessionTask(
                        head: Self.head(status: 200, headers: [("Upload-Offset", "100"), ("Upload-Length", "1000")])
                    )
                case "PATCH":
                    let count = patches.withLockedValue { value -> Int in
                        value += 1
                        return value
                    }

                    let offset = Int(configuration.headers.first(name: "Upload-Offset") ?? "0") ?? 0

                    switch count {
                    case 1:
                        return await Self.sessionTask(head: Self.head(status: 204, headers: [("Upload-Offset", "600")]))
                    case 2:
                        return await Self.sessionTask(head: Self.head(status: 409))
                    default:
                        return await Self.sessionTask(
                            head: Self.head(status: 204, headers: [("Upload-Offset", String(min(offset + 100, 1_000)))])
                        )
                    }
                default:
                    return await Self.sessionTask(head: Self.head(status: 204))
                }
            }
        )

        execution.start()
        for try await _ in execution.response {}

        #expect(patches.withLockedValue { $0 } == 11)
    }

    /// The server held 600 once, lost data, and now keeps 100 bytes of each `PATCH`: until it is
    /// past 600 again, every answer is past where that attempt began and short of the 600 it once
    /// held. None is charged to the budget (the upload does finish), but each waits, or the number
    /// of attempts made back to back would depend on the size of the upload and each would resend
    /// the rest of the body.
    @Test
    func aPartialAnswerBelowTheFurthestTheServerHeld_waitsWithoutSpendingTheBudget() async throws {
        let events = LockedValueBox<[String]>([])
        let patches = LockedValueBox(0)

        let execution = try await Self.execution(
            dialect: TUSResumableUploadDialect(),
            delay: 7,
            sleep: { delay in events.withLockedValue { $0.append("wait \(delay)") } },
            client: ScriptedClient { configuration in
                switch configuration.method {
                case "POST":
                    return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
                case "HEAD":
                    return await Self.sessionTask(
                        head: Self.head(status: 200, headers: [("Upload-Offset", "100"), ("Upload-Length", "1000")])
                    )
                case "PATCH":
                    let count = patches.withLockedValue { value -> Int in
                        value += 1
                        return value
                    }

                    let offset = Int(configuration.headers.first(name: "Upload-Offset") ?? "0") ?? 0
                    events.withLockedValue { $0.append("PATCH \(offset)") }

                    switch count {
                    case 1:
                        return await Self.sessionTask(head: Self.head(status: 204, headers: [("Upload-Offset", "600")]))
                    case 2:
                        return await Self.sessionTask(head: Self.head(status: 409))
                    default:
                        return await Self.sessionTask(
                            head: Self.head(status: 204, headers: [("Upload-Offset", String(min(offset + 100, 1_000)))])
                        )
                    }
                default:
                    return await Self.sessionTask(head: Self.head(status: 204))
                }
            }
        )

        execution.start()
        for try await _ in execution.response {}

        // The conflict that moved nothing waited, and so did each answer that climbed back up to the
        // 600 and no further. Past it, the upload moves, and does not wait.
        #expect(
            events.withLockedValue { $0 } == [
                "PATCH 0", "PATCH 600", "wait 7",
                "PATCH 100", "wait 7", "PATCH 200", "wait 7", "PATCH 300", "wait 7",
                "PATCH 400", "wait 7", "PATCH 500", "wait 7",
                "PATCH 600", "PATCH 700", "PATCH 800", "PATCH 900",
            ]
        )
    }

    /// tus: a partial answer that holds nothing new waits like any other attempt that moved nothing.
    @Test
    func aPartialAnswerThatHoldsNothingNew_waitsBeforeTheNextAttempt() async throws {
        let events = LockedValueBox<[String]>([])

        let execution = try await Self.execution(
            dialect: TUSResumableUploadDialect(),
            delay: 7,
            sleep: { delay in events.withLockedValue { $0.append("wait \(delay)") } },
            client: ScriptedClient { configuration in
                guard configuration.method == "PATCH" else {
                    return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
                }

                events.withLockedValue { $0.append("PATCH") }
                return await Self.sessionTask(head: Self.head(status: 204, headers: [("Upload-Offset", "0")]))
            }
        )

        execution.start()

        await #expect(throws: UploadResumptionError(.conflictingOffsets)) {
            for try await _ in execution.response {}
        }

        #expect(events.withLockedValue { $0 } == ["PATCH", "wait 7", "PATCH", "wait 7", "PATCH", "wait 7", "PATCH"])
    }

    @Test
    func aTusUploadWithAContentEncodingOnAnyLine_isRefused() async throws {
        var configuration = RequestConfiguration()
        configuration.headers.set(name: "Content-Encoding", value: "identity")
        configuration.headers.add(name: "Content-Encoding", value: "gzip")

        #expect(throws: UploadResumptionError(.contentEncodingNotSupported)) {
            try TUSResumableUploadDialect().validate(configuration)
        }

        configuration.headers.set(name: "Content-Encoding", value: "identity")
        #expect(throws: Never.self) {
            try TUSResumableUploadDialect().validate(configuration)
        }
    }

    // MARK: - Where the upload lives

    @Test
    func anUploadURLThatEndsInASlash_isSentToWithTheSlash() async throws {
        // Given
        let urls = LockedValueBox<[String: String]>([:])

        let execution = try await Self.execution(
            client: ScriptedClient { configuration in
                urls.withLockedValue { $0[configuration.method ?? ""] = configuration.url }

                if configuration.method == "PATCH" {
                    return await Self.sessionTask(head: Self.head(status: 200))
                }

                return await Self.sessionTask(
                    head: Self.head(status: 201, headers: [("Location", "https://example.com/files/abc/")])
                )
            }
        )

        // When
        execution.start()
        for try await _ in execution.response {}

        // Then
        #expect(urls.withLockedValue { $0["PATCH"] } == "https://example.com/files/abc/")
    }

    // MARK: - Cancelling, again

    @Test
    func cancellingTwice_tellsTheServerOnce() async throws {
        // Given: a body that is being sent.
        let methods = LockedValueBox<[String]>([])
        let gate = Gate()

        let execution = try await Self.execution(
            client: ScriptedClient { configuration in
                methods.withLockedValue { $0.append(configuration.method ?? "") }

                if configuration.method == "PATCH" {
                    await gate.wait()
                }

                return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
            }
        )

        execution.start()
        try await eventually { methods.withLockedValue { $0 }.contains("PATCH") }

        // When: whoever holds the response, and the seed it dropped, both end it.
        execution.cancel()
        execution.cancel()
        gate.open()

        // Then
        try await eventually { methods.withLockedValue { $0 }.contains("DELETE") }
        try await _Concurrency.Task.sleep(nanoseconds: 300_000_000)
        #expect(methods.withLockedValue { $0 }.filter { $0 == "DELETE" }.count == 1)
    }

    @Test
    func cancellingWhileTheResponseWaitsForItsReader_endsTheUpload() async throws {
        // Given: a response whose body nobody reads, so the execution is held back in front of
        // room that is never made.
        let delivered = LockedValueBox(false)
        let reference = WeakReference<ResumableUploadExecution>()

        do {
            let execution = try await Self.execution(
                client: ScriptedClient { configuration in
                    if configuration.method == "PATCH" {
                        delivered.withLockedValue { $0 = true }
                        return await Self.sessionTask(
                            head: Self.head(status: 200),
                            body: .piecesThenEndless(count: 8, size: 1_048_576)
                        )
                    }

                    return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
                }
            )

            reference.value = execution
            execution.start()

            try await eventually { delivered.withLockedValue { $0 } }
            try await _Concurrency.Task.sleep(nanoseconds: 500_000_000)

            // When
            execution.cancel()
        }

        // Then: nothing is left holding the execution.
        try await eventually(timeout: 10) { reference.value == nil }
    }

    // MARK: - A body that breaks

    @Test
    func aResponseBodyThatBreaksAfterItsHead_failsTheBody() async throws {
        // Given
        let execution = try await Self.execution(
            client: ScriptedClient { configuration in
                if configuration.method == "PATCH" {
                    return await Self.sessionTask(
                        head: Self.head(status: 200),
                        body: .failure(StubError())
                    )
                }

                return await Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
            }
        )

        // When
        execution.start()

        // Then: the head is handed over, and the body is what fails.
        var iterator = execution.response.makeAsyncIterator()
        var step = try await iterator.next()

        while case .upload = step {
            step = try await iterator.next()
        }

        guard case .download(let download) = step else {
            Issue.record("Expected the response of the upload")
            return
        }

        #expect(download.head.status.code == 200)

        await #expect(throws: StubError.self) {
            for try await _ in download.bytes {}
        }
    }

    // MARK: - The client

    @Test
    func theClient_asksTheClientItWrapsToRevalidate() async throws {
        // Given
        let client = ResumableUploadClient(
            base: ScriptedClient { _ in throw StubError() },
            setup: ResumableUploadSetup(dialect: IETFResumableUploadDialect())
        )

        // When
        let head = try await client.revalidationHead(
            configuration: RequestConfiguration(),
            logger: nil,
            metrics: nil
        )

        // Then
        #expect(head.status.code == 304)
    }

    @Test
    func theClient_refusesABodyWhoseEncodingTheProtocolCannotCarry() async throws {
        // Given: a body that was compressed, which says so in `Content-Encoding`, for a protocol that
        // sends the request that carries the bytes without it.
        let sent = LockedValueBox(false)

        let client = ResumableUploadClient(
            base: ScriptedClient { _ in
                sent.withLockedValue { $0 = true }
                throw StubError()
            },
            setup: ResumableUploadSetup(dialect: TUSResumableUploadDialect())
        )

        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com"
        configuration.method = "PUT"
        configuration.headers.set(name: "Content-Encoding", value: "gzip")
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(Data(repeating: 1, count: 100))])

        // Then: nothing was sent, and the caller is told why.
        await #expect(throws: UploadResumptionError(.contentEncodingNotSupported)) {
            _ = try await client.execute(
                configuration: configuration,
                decompression: .disabled,
                cache: nil,
                logger: nil,
                transferControl: nil
            )
        }

        #expect(!sent.withLockedValue { $0 })
    }

    @Test
    func theClient_doesNotRefuseAnEncodedBodyWhereTheProtocolCarriesTheEncoding() async throws {
        // Given: the IETF protocol creates the upload with the request that was written.
        let client = ResumableUploadClient(
            base: ScriptedClient { _ in throw StubError() },
            setup: ResumableUploadSetup(dialect: IETFResumableUploadDialect())
        )

        var configuration = RequestConfiguration()
        configuration.baseURL = "https://example.com"
        configuration.method = "PUT"
        configuration.headers.set(name: "Content-Encoding", value: "gzip")
        configuration.body = await RequestBody(buffers: [Internals.DataBuffer(Data(repeating: 1, count: 100))])

        // When
        let task = try await client.execute(
            configuration: configuration,
            decompression: .disabled,
            cache: nil,
            logger: nil,
            transferControl: nil
        )

        // Then: it ran, and failed only because the executor did.
        await #expect(throws: StubError.self) {
            for try await _ in task.response {}
        }
    }

    // MARK: - Helpers

    private final class WeakReference<Object: AnyObject>: @unchecked Sendable {
        weak var value: Object?
    }

    private final class Gate: @unchecked Sendable {

        private let lock = Lock()
        private var _isOpen = false
        private var _waiting: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { continuation in
                let isOpen = lock.withLock { () -> Bool in
                    guard !_isOpen else {
                        return true
                    }

                    _waiting.append(continuation)
                    return false
                }

                if isOpen {
                    continuation.resume()
                }
            }
        }

        func open() {
            let waiting = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
                _isOpen = true
                defer { _waiting = [] }
                return _waiting
            }

            for continuation in waiting {
                continuation.resume()
            }
        }
    }

    private static func head(status: UInt, headers: [(String, String)] = []) -> Internals.ResponseHead {
        Internals.ResponseHead(
            url: "https://example.com",
            status: .init(code: status, reason: ""),
            version: .init(minor: 1, major: 1),
            headers: headers.map { .init(name: $0.0, value: $0.1) },
            isKeepAlive: true
        )
    }

    private enum Body {
        case success(Data)
        case failure(Error)

        /// A body that has begun and never ends.
        case endless

        /// A body that gives `count` pieces of `size` bytes and then never ends.
        case piecesThenEndless(count: Int, size: Int)
    }

    private static func sessionTask(
        head: Internals.ResponseHead,
        body: Body = .success(Data()),
        seed: Internals.TaskSeed = .withoutCancellation
    ) async -> SessionTask {
        let upload = Internals.AsyncStream<Int>()
        let heads = Internals.AsyncStream<Internals.ResponseHead>()
        let download = Internals.AsyncStream<Internals.Chunk>()

        upload.close()
        heads.append(.success(head))
        heads.close()

        switch body {
        case .success:
            download.close()
        case .failure(let error):
            download.append(.failure(error))
        case .endless:
            break
        case .piecesThenEndless(let count, let size):
            for _ in 0..<count {
                download.append(.success(Internals.Chunk(Data(repeating: 7, count: size))))
            }
        }

        return SessionTask(
            seed: seed,
            response: Internals.AsyncResponse(
                logger: nil,
                uploadingBytes: 0,
                upload: upload,
                decompressionDispatch: .skip,
                readingMode: .passthrough,
                head: heads,
                download: download
            )
        )
    }

    private static func execution(
        dialect: any ResumableUploadDialect = IETFResumableUploadDialect(),
        cancellation: UploadCancellation = .terminate,
        forwardsCredentialsToOtherOrigins: Bool = false,
        delay: UInt64 = 1_000_000,
        sleep: (@Sendable (UInt64) async throws -> Void)? = nil,
        client: ScriptedClient
    ) async throws -> ResumableUploadExecution {
        var request = RequestConfiguration()
        request.baseURL = "https://example.com"
        request.pathComponents = ["files"]
        request.method = "PUT"
        request.headers.set(name: "Authorization", value: "Bearer token")

        let source = try await ResumableUploadSource(
            RequestBody(buffers: [Internals.DataBuffer(Data(repeating: 1, count: 1_000))])
        )

        return await ResumableUploadExecution(
            client: client,
            setup: ResumableUploadSetup(
                dialect: dialect,
                delay: delay,
                cancellation: cancellation,
                forwardsCredentialsToOtherOrigins: forwardsCredentialsToOtherOrigins,
                sleep: sleep ?? { try await Task.sleep(nanoseconds: $0) }
            ),
            request: request,
            source: source,
            decompression: .disabled,
            logger: nil,
            control: nil
        )
    }
}

/// The IETF dialect, for a protocol that has no way to tell a server an upload is abandoned.
private struct NoCancellationDialect: ResumableUploadDialect {

    private let base = IETFResumableUploadDialect()

    var requiresKnownLength: Bool { base.requiresKnownLength }

    func creation(for request: RequestConfiguration, length: Int64?) -> RequestConfiguration {
        base.creation(for: request, length: length)
    }

    func resource(from head: ResponseHead, createdFor request: RequestConfiguration) throws -> UploadResource {
        try base.resource(from: head, createdFor: request)
    }

    func offsetQuery(for resource: UploadResource, like request: RequestConfiguration) -> RequestConfiguration {
        base.offsetQuery(for: resource, like: request)
    }

    func report(from head: ResponseHead) throws -> UploadOffsetReport {
        try base.report(from: head)
    }

    func append(
        to resource: UploadResource,
        from offset: Int64,
        like request: RequestConfiguration
    ) -> RequestConfiguration {
        base.append(to: resource, from: offset, like: request)
    }

    func outcome(of head: ResponseHead, offset: Int64, length: Int64?) -> UploadAppendOutcome {
        base.outcome(of: head, offset: offset, length: length)
    }

    func completionResponse(from head: ResponseHead) -> ResponseHead? {
        base.completionResponse(from: head)
    }

    func cancellation(of resource: UploadResource, like request: RequestConfiguration) -> RequestConfiguration? {
        nil
    }
}
