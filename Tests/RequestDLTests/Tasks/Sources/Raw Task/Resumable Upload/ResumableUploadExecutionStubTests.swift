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
            cache: (@Sendable (Internals.ResponseHead) -> Internals.AsyncStream<Internals.DataBuffer>?)?,
            logger: Internals.TaskLogger?,
            transferControl: Internals.TransferControl?
        ) async throws -> SessionTask {
            try await script(configuration)
        }

        func revalidationHead(
            configuration: RequestConfiguration,
            logger: Internals.TaskLogger?
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

                return Self.sessionTask(
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

                return Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
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

                return Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
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

                return Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
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
                return Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
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
                    return Self.sessionTask(head: Self.head(status: 200), body: .endless)
                }

                return Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
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

                return Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
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

    // MARK: - A body that breaks

    @Test
    func aResponseBodyThatBreaksAfterItsHead_failsTheBody() async throws {
        // Given
        let execution = try await Self.execution(
            client: ScriptedClient { configuration in
                if configuration.method == "PATCH" {
                    return Self.sessionTask(
                        head: Self.head(status: 200),
                        body: .failure(StubError())
                    )
                }

                return Self.sessionTask(head: Self.head(status: 201, headers: [("Location", "/uploads/1")]))
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
        let head = try await client.revalidationHead(configuration: RequestConfiguration(), logger: nil)

        // Then
        #expect(head.status.code == 304)
    }

    // MARK: - Helpers

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
    }

    private static func sessionTask(
        head: Internals.ResponseHead,
        body: Body = .success(Data()),
        seed: Internals.TaskSeed = .withoutCancellation
    ) -> SessionTask {
        let upload = Internals.AsyncStream<Int>()
        let heads = Internals.AsyncStream<Internals.ResponseHead>()
        let download = Internals.AsyncStream<Internals.DataBuffer>()

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
        }

        return SessionTask(
            seed: seed,
            response: Internals.AsyncResponse(
                logger: nil,
                uploadingBytes: 0,
                upload: upload,
                decompressionDispatch: .skip,
                head: heads,
                download: download
            )
        )
    }

    private static func execution(
        dialect: any ResumableUploadDialect = IETFResumableUploadDialect(),
        cancellation: UploadCancellation = .terminate,
        client: ScriptedClient
    ) async throws -> ResumableUploadExecution {
        var request = RequestConfiguration()
        request.baseURL = "https://example.com"
        request.pathComponents = ["files"]
        request.method = "PUT"

        let source = try await ResumableUploadSource(
            RequestBody(buffers: [Internals.DataBuffer(Data(repeating: 1, count: 1_000))])
        )

        return await ResumableUploadExecution(
            client: client,
            setup: ResumableUploadSetup(
                dialect: dialect,
                delay: 1_000_000,
                cancellation: cancellation
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
