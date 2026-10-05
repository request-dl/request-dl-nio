//
// See LICENSE for this package's licensing information.
//

import RequestDLInternals
import SwiftAsyncStream

#if canImport(FoundationEssentials)
import struct FoundationEssentials.Data
#else
import struct Foundation.Data
#endif

/// One resumable upload, from its creation to the response of the application: the part of the
/// work that is the same for every protocol and every executor.
///
/// It is what the executors already are for a download that reconnects (`NIODownloadReconnection`,
/// `URLSessionClient.resumeDownload`), on the sending side, and written once for all of them:
/// every request goes through the executor the caller chose, so an upload behaves the same on
/// `.nio`, `.nioTransportServices` and `.urlSession`.
///
/// ## What it does
///
/// 1. Creates the upload, with the request the dialect builds from the one the caller wrote.
/// 2. Sends the body to the upload, from the offset the server holds.
/// 3. If the connection is lost, or the server answers "not now": waits while suspended, waits
///    ``ResumableUploadSetup/delay``, asks the server how much of the upload it holds, and sends
///    the rest from there. The count of attempts that end with the server holding nothing new
///    starts over whenever it does.
/// 4. Hands the response to the `PATCH` that completes the upload to the caller, as the response
///    of the request they wrote, and nothing else: not what answered the creation, an offset
///    query, or a `PATCH` that had to be sent again.
///
/// The one exception is a creation that is answered with something that is not a success: that
/// response is the response of the upload, since it is what the server has to say about the
/// request the caller wrote (a `401`, say), which is what they would have got without any of this.
///
/// ## What it reports
///
/// Upload progress is what crosses the network, over every attempt, so the bytes sent again after
/// a loss count again.
final class ResumableUploadExecution: @unchecked Sendable {

    // MARK: - Private types

    /// An exchange that has produced its head.
    private struct Exchange {
        let head: Internals.ResponseHead
        let bytes: Internals.AsyncBytes
        let seed: Internals.TaskSeed
        let relay: ResumableUploadExchangeRelay?

        /// Not the response of the upload: nobody wants what is left of it.
        func discard() {
            relay?.discard()
            seed()
        }
    }

    private struct Budget {
        var withoutProgress = 0
        var attempts = 0
        var knownOffset: Int64 = 0
    }

    // MARK: - Internal properties

    let response: Internals.AsyncResponse

    /// What cancels the upload, and what goes away with the response that was given out, which
    /// cancels it too.
    ///
    /// Made for whoever holds the response, and not kept here: the execution holding its own seed
    /// would be a cycle, and a response that was dropped would never be noticed.
    func makeSeed() -> Internals.TaskSeed {
        Internals.TaskSeed(
            cancel: { [self] in cancel() },
            release: { [self] in cancel() }
        )
    }

    // MARK: - Private properties

    private let client: any RequestExecutingClient
    private let setup: ResumableUploadSetup
    private let request: RequestConfiguration
    private let source: ResumableUploadSource
    private let decompression: Internals.Decompression
    private let logger: Internals.TaskLogger?
    private let control: Internals.TransferControl?

    private let upload: Internals.AsyncStream<Int>
    private let head: Internals.AsyncStream<Internals.ResponseHead>
    private let download: Internals.DownloadBuffer
    private let window: Internals.FlowControlWindow

    private let lock = Lock()

    // MARK: - Unsafe properties

    private var _task: Task<Void, Never>?
    private var _current: Internals.TaskSeed?
    private var _isCancelled = false
    private var _isOver = false

    // MARK: - Inits

    init(
        client: any RequestExecutingClient,
        setup: ResumableUploadSetup,
        request: RequestConfiguration,
        source: ResumableUploadSource,
        decompression: Internals.Decompression,
        logger: Internals.TaskLogger?,
        control: Internals.TransferControl?
    ) async {
        self.client = client
        self.setup = setup
        self.request = request
        self.source = source
        self.decompression = decompression
        self.logger = logger
        self.control = control

        let upload = Internals.AsyncStream<Int>()
        let head = Internals.AsyncStream<Internals.ResponseHead>()
        let window = Internals.FlowControlWindow()
        let download = await Internals.DownloadBuffer(
            readingMode: request.readingMode,
            flowControl: window,
            observer: nil
        )

        self.upload = upload
        self.head = head
        self.window = window
        self.download = download

        self.response = Internals.AsyncResponse(
            logger: logger,
            uploadingBytes: Int(clamping: source.length),
            upload: upload,
            // What the exchange that is the response hands over is already decoded.
            decompressionDispatch: .skip,
            head: head,
            download: download.stream
        )
    }

    // MARK: - Internal methods

    func start() {
        // Once the upload is over this task is the last thing holding the execution, which is
        // what lets a response that was dropped be cancelled: the seed only reaches it through
        // `cancel()`, never the other way around.
        let task = Task { [self] in
            await run()
        }

        let isCancelled = lock.withLock { () -> Bool in
            _task = task
            return _isCancelled
        }

        if isCancelled {
            task.cancel()
        }
    }

    /// Ends the upload: the exchange in flight is cancelled and the suspension, if any, lifted so
    /// that nothing keeps waiting. The upload stays on the server, which is left to expire it.
    func cancel() {
        let (task, current) = lock.withLock { () -> (Task<Void, Never>?, Internals.TaskSeed?) in
            guard !_isOver else {
                return (nil, nil)
            }

            _isCancelled = true
            return (_task, _current)
        }

        control?.release()
        task?.cancel()
        current?()
    }

    // MARK: - Private methods

    private func run() async {
        do {
            try await perform()
            finishQuietly()
        } catch {
            fail(error)
        }
    }

    private func perform() async throws {
        control?.observer?.expectUpload(Int(clamping: source.length))

        // 1. The upload is created.
        let creation = setup.dialect.creation(for: request, length: source.length)
        let created = try await exchange(creation)
        let createdHead = ResponseHead(created.head)

        guard (200..<300).contains(createdHead.status.code) else {
            try await forward(created)
            return
        }

        let resource: UploadResource

        do {
            resource = try setup.dialect.resource(from: createdHead, createdFor: request)
            created.discard()
        } catch {
            created.discard()
            throw ResumableUploadError(reason: .notSupported)
        }

        // 2. Its body is sent, and sent again from wherever the server says it is.
        var budget = Budget()

        while true {
            try checkNotCancelled()
            await control?.waitUntilResumed()
            try checkNotCancelled()

            // The first attempt isn't counted: it is the others, the ones that follow a loss or a
            // disagreement, that are allowed to go without moving anything only so many times.
            guard budget.withoutProgress <= setup.maximumAttemptsWithoutProgress else {
                throw ResumableUploadError(reason: .conflictingOffsets)
            }

            var append = setup.dialect.append(to: resource, from: budget.knownOffset, like: request)
            append.body = source.remaining(from: budget.knownOffset)

            let failure: Error

            do {
                let sent = try await exchange(append)

                switch setup.dialect.outcome(
                    of: ResponseHead(sent.head),
                    offset: budget.knownOffset,
                    length: source.length
                ) {
                case .finished, .other:
                    try await forward(sent)
                    return

                case .partial(let held):
                    sent.discard()
                    try advance(&budget, to: held)
                    continue

                case .conflict(let held):
                    sent.discard()
                    budget.attempts += 1

                    let adopted: Int64

                    if let held {
                        adopted = held
                    } else {
                        adopted = try await queryOffset(resource).report.offset
                    }

                    try advance(&budget, to: adopted, countsAsAttempt: true)
                    continue

                case .gone:
                    sent.discard()
                    throw ResumableUploadError(reason: .uploadLost(status: UInt(sent.head.status.code)))
                }
            } catch {
                guard Self.isTransient(error) else {
                    throw error
                }

                failure = error
            }

            // 3. The attempt failed, in a way that another one may not.
            if let completed = try await recover(resource, after: failure, budget: &budget) {
                try await forwardCompletion(completed)
                return
            }
        }
    }

    /// Asks the server where the upload stands, until it says, and moves the budget there.
    ///
    /// - Returns: The response to the offset query, if it says the upload is complete: the
    ///   `PATCH` that completed it got its answer lost.
    private func recover(
        _ resource: UploadResource,
        after failure: Error,
        budget: inout Budget
    ) async throws -> ResponseHead? {
        var failure = failure

        while true {
            guard budget.withoutProgress < setup.maximumAttemptsWithoutProgress else {
                throw failure
            }

            budget.attempts += 1
            control?.observer?.didChange(.reconnecting(attempt: budget.attempts))

            if setup.delay > .zero {
                try await Task.sleep(nanoseconds: setup.delay)
            }

            try checkNotCancelled()
            await control?.waitUntilResumed()
            try checkNotCancelled()

            do {
                let (report, head) = try await queryOffset(resource)
                try advance(&budget, to: report.offset, countsAsAttempt: true)

                if report.isComplete || report.offset >= source.length {
                    return head
                }

                return nil
            } catch {
                guard Self.isTransient(error) else {
                    throw error
                }

                budget.withoutProgress += 1
                failure = error
            }
        }
    }

    private func queryOffset(
        _ resource: UploadResource
    ) async throws -> (report: UploadOffsetReport, head: ResponseHead) {
        let query = setup.dialect.offsetQuery(for: resource, like: request)
        let exchange = try await exchange(query)
        let head = ResponseHead(exchange.head)

        exchange.discard()

        switch head.status.code {
        case 404, 410:
            throw ResumableUploadError(reason: .uploadLost(status: head.status.code))
        case 408, 425, 429, 500..<600:
            throw ResumableUploadTransientResponse(status: head.status.code)
        default:
            break
        }

        do {
            return (try setup.dialect.report(from: head), head)
        } catch {
            throw ResumableUploadError(reason: .offsetRejected(status: head.status.code))
        }
    }

    /// Moves what is known of the server to `offset`.
    private func advance(_ budget: inout Budget, to offset: Int64, countsAsAttempt: Bool = false) throws {
        guard offset <= source.length else {
            throw ResumableUploadError(reason: .offsetBeyondLength(offset: offset, length: source.length))
        }

        if offset > budget.knownOffset {
            budget.withoutProgress = .zero
        } else if countsAsAttempt {
            budget.withoutProgress += 1
        }

        budget.knownOffset = offset
    }

    // MARK: - Private methods, exchanges

    private func exchange(_ configuration: RequestConfiguration) async throws -> Exchange {
        try checkNotCancelled()

        let relay = control.map { ResumableUploadExchangeRelay(parent: $0) }

        let task: SessionTask

        do {
            task = try await client.execute(
                configuration: configuration,
                decompression: decompression,
                cache: nil,
                logger: logger,
                transferControl: relay?.control
            )
        } catch {
            relay?.discard()
            throw error
        }

        let isCancelled = lock.withLock { () -> Bool in
            _current = task.seed
            return _isCancelled
        }

        if isCancelled {
            task.seed()
        }

        var iterator = task.response.makeAsyncIterator()

        do {
            while let step = try await iterator.next() {
                switch step {
                case .upload(let step):
                    upload.append(.success(step.chunkSize))

                case .download(let step):
                    return Exchange(head: step.head, bytes: step.bytes, seed: task.seed, relay: relay)
                }
            }

            throw RequestFailureError()
        } catch {
            relay?.discard()
            task.seed()
            throw error
        }
    }

    /// The exchange is the response of the upload: what it says, and its body, are handed over.
    private func forward(_ exchange: Exchange) async throws {
        exchange.relay?.decide(final: exchange.head)

        upload.close()
        head.append(.success(exchange.head))
        head.close()

        do {
            for try await data in exchange.bytes {
                await window.waitUntilWritable()
                download.append(await Internals.DataBuffer(data))
            }
        } catch {
            exchange.seed()
            throw error
        }

        download.close()
    }

    /// The upload is complete on the server but its response was lost, and the protocol says the
    /// answer to the query for the offset is as good: that is what is handed over, with no body.
    private func forwardCompletion(_ queried: ResponseHead) async throws {
        guard let completion = setup.dialect.completionResponse(from: queried) else {
            throw ResumableUploadError(reason: .completedWithoutResponse)
        }

        upload.close()
        head.append(.success(completion.internalHead))
        head.close()
        download.close()

        control?.observer?.didReceiveHead(completion.internalHead)
        control?.observer?.didChange(.finished)
    }

    // MARK: - Private methods, ending

    private func finishQuietly() {
        lock.withLock { _isOver = true }
        control?.release()
    }

    private func fail(_ error: Error) {
        lock.withLock { _isOver = true }

        upload.append(.failure(error))
        head.append(.failure(error))
        download.failed(error)

        control?.observer?.didChange(.failed(error))
        control?.release()
    }

    private func checkNotCancelled() throws {
        if lock.withLock({ _isCancelled }) || Task.isCancelled {
            throw CancellationError()
        }
    }

    /// Whether `error` means "try again" rather than "no".
    private static func isTransient(_ error: Error) -> Bool {
        if error is ResumableUploadTransientResponse {
            return true
        }

        #if canImport(NIOCore)
        if Internals.NIODownloadReconnection.isTransientTransportFailure(error) {
            return true
        }
        #endif

        #if canImport(Darwin)
        if Internals.URLSessionClient.isTransientTransportFailure(error) {
            return true
        }
        #endif

        return false
    }
}

extension ResponseHead {

    /// The transport layer's form of this head, for handing it over as a response.
    fileprivate var internalHead: Internals.ResponseHead {
        Internals.ResponseHead(
            url: url?.absoluteString ?? "",
            status: .init(code: status.code, reason: status.reason),
            version: .init(minor: version.minor, major: version.major),
            headers: headers.map { .init(name: $0.name, value: $0.value) },
            isKeepAlive: isKeepAlive
        )
    }
}
