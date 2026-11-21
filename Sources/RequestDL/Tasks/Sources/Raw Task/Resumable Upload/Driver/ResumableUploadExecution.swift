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

        /// Where the server last said it was, which is where the next attempt starts from.
        var knownOffset: Int64 = 0

        /// The furthest the server has ever said it was. Progress is getting past this, not past
        /// `knownOffset`: a server that answers from replicas that hold different amounts of the
        /// upload says 10, then 5, then 10, and every one of those would otherwise be "more than
        /// the last".
        var highestOffset: Int64 = 0
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
    private var _resource: UploadResource?
    private var _isComplete = false

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
        var request = request
        request.forwardsCredentialsToOtherOrigins = setup.forwardsCredentialsToOtherOrigins

        self.request = request
        self.source = source
        self.decompression = decompression
        self.logger = logger
        self.control = control

        // Left `.unbounded` on purpose: the response replays its upload steps to every iterator, which is
        // part of what `AsyncResponse` has always done (see `InternalsAsyncResponseTests`). Retaining one
        // small entry per uploaded part does not justify changing that contract.
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
            readingMode: request.readingMode,
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
    /// that nothing keeps waiting. If there is an upload on the server that isn't complete, and
    /// the setup says so, the server is told it is abandoned, in the background.
    func cancel() {
        let (task, current, abandoned) = lock.withLock {
            () -> (Task<Void, Never>?, Internals.TaskSeed?, UploadResource?) in
            // Once is all it takes: the server is told once, however many of the handles that end
            // the upload (the seed, the response that was dropped) get to it.
            guard !_isOver, !_isCancelled else {
                return (nil, nil, nil)
            }

            _isCancelled = true

            let isAbandoned = setup.cancellation == .terminate && !_isComplete
            return (_task, _current, isAbandoned ? _resource : nil)
        }

        control?.release()

        // What keeps the execution parked in front of a reader that never makes room for the body
        // of a response: it is not cancellable on its own, so it is opened, and what follows is the
        // exchange, which is cancelled below, failing.
        window.release()

        task?.cancel()
        current?()

        if let abandoned {
            terminate(abandoned)
        }
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
            throw UploadResumptionError(.notSupported)
        }

        lock.withLock { _resource = resource }

        // 2. Its body is sent, and sent again from wherever the server says it is.
        var budget = Budget()

        while true {
            try checkNotCancelled()
            await control?.waitUntilResumed()
            try checkNotCancelled()

            // The first attempt isn't counted: it is the others, the ones that follow a loss or a
            // disagreement, that are allowed to go without moving anything only so many times.
            guard budget.withoutProgress <= setup.maximumAttemptsWithoutProgress else {
                throw UploadResumptionError(.conflictingOffsets)
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
                    // An answer that holds no more than was already known moved nothing, and
                    // must spend the budget like any other attempt that did not.
                    sent.discard()

                    // What this attempt sent from: bytes the server took past it are progress of
                    // this attempt even when the server held more before it lost some.
                    let sentFrom = budget.knownOffset

                    if try advance(&budget, to: held, countsAsAttempt: true, acceptedFrom: sentFrom) {
                        try await pauseUnlessGivingUp(budget)
                    }

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

                    if try advance(&budget, to: adopted, countsAsAttempt: true) {
                        try await pauseUnlessGivingUp(budget)
                    }

                    continue

                case .gone:
                    sent.discard()
                    throw UploadResumptionError(.uploadLost(status: UInt(sent.head.status.code)))
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
                throw Self.surfaced(failure)
            }

            budget.attempts += 1
            control?.observer?.didChange(.reconnecting(attempt: budget.attempts))

            try await pause()
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
            throw UploadResumptionError(.uploadLost(status: head.status.code))
        case 408, 425, 429, 500..<600:
            throw ResumableUploadTransientResponse(status: head.status.code)
        default:
            break
        }

        do {
            return (try setup.dialect.report(from: head), head)
        } catch {
            throw UploadResumptionError(.offsetRejected(status: head.status.code))
        }
    }

    /// Waits ``ResumableUploadSetup/delay``, which is what keeps a server that does not make up its
    /// mind from being asked again as fast as it answers.
    private func pause() async throws {
        if setup.delay > .zero {
            try await setup.sleep(setup.delay)
        }

        try checkNotCancelled()
    }

    /// ``pause()``, unless the budget is spent and the next thing that happens is the failure: it
    /// would only arrive late.
    private func pauseUnlessGivingUp(_ budget: Budget) async throws {
        guard budget.withoutProgress <= setup.maximumAttemptsWithoutProgress else {
            return
        }

        try await pause()
    }

    /// Moves what is known of the server to `offset`.
    ///
    /// - Parameter start: Where the attempt this answers began, when the answer says how much the
    ///   server kept of it: an offset past it, though not past the furthest the server ever held,
    ///   is neither progress nor a stall.
    /// - Returns: Whether to wait before asking again: this attempt got nowhere past the furthest
    ///   the server was ever said to be. That spends the budget when it moved nothing at all; when
    ///   it took bytes, but not past that furthest, it waits without spending it.
    @discardableResult
    private func advance(
        _ budget: inout Budget,
        to offset: Int64,
        countsAsAttempt: Bool = false,
        acceptedFrom start: Int64? = nil
    ) throws -> Bool {
        guard offset <= source.length else {
            throw UploadResumptionError(.offsetBeyondLength(offset: offset, length: source.length))
        }

        var isStalled = false

        if offset > budget.highestOffset {
            budget.withoutProgress = .zero
            budget.highestOffset = offset
        } else if let start, offset > start {
            // The server took bytes of this attempt: it moved, only not past where it once was, so
            // the budget is not charged. It still waits: how many of these there can be depends on
            // the size of the upload, and not on the budget, so without a wait a server that keeps
            // one byte of each attempt would be asked again, with the rest of the body, as fast as
            // it answers.
            isStalled = true
        } else if countsAsAttempt {
            budget.withoutProgress += 1
            isStalled = true
        }

        budget.knownOffset = offset
        return isStalled
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
        // Past this point the upload is whole on the server, if it was ever created.
        lock.withLock { _isComplete = true }
        exchange.relay?.decide(final: exchange.head)

        upload.close()
        head.append(.success(exchange.head))
        head.close()

        do {
            for try await data in exchange.bytes {
                await window.waitUntilWritable()

                // Opened by a cancellation as much as by a reader that made room: only the first
                // goes on.
                try checkNotCancelled()

                download.append(await Internals.DataBuffer(data))
            }
        } catch {
            exchange.seed()
            throw error
        }

        // An exchange that was cancelled may simply end: that is not a body that is whole.
        try checkNotCancelled()

        download.close()
    }

    /// The upload is complete on the server but its response was lost, and the protocol says the
    /// answer to the query for the offset is as good: that is what is handed over, with no body.
    private func forwardCompletion(_ queried: ResponseHead) async throws {
        lock.withLock { _isComplete = true }

        guard let completion = setup.dialect.completionResponse(from: queried) else {
            throw UploadResumptionError(.completedWithoutResponse)
        }

        upload.close()
        head.append(.success(completion.internalHead))
        head.close()
        download.close()

        control?.observer?.didReceiveHead(completion.internalHead)
        control?.observer?.didChange(.finished)
    }

    // MARK: - Private methods, cancellation

    /// How long the server is given to answer that an upload was abandoned.
    private static let terminationTimeout: Int64 = 5_000_000_000

    /// Tells the server the upload is abandoned, if the protocol has a way to, and doesn't wait for
    /// the answer: whoever cancelled has moved on, and a server that doesn't answer is not a reason
    /// to keep anything alive. Not sent through this execution's control, which is released.
    private func terminate(_ resource: UploadResource) {
        guard let termination = setup.dialect.cancellation(of: resource, like: request) else {
            return
        }

        let client = client
        let decompression = decompression
        let logger = logger

        Task.detached(priority: .utility) {
            guard
                let task = try? await client.execute(
                    configuration: termination,
                    decompression: decompression,
                    cache: nil,
                    logger: logger,
                    transferControl: nil
                )
            else {
                return
            }

            let deadline = Internals.ResourceDeadline(nanoseconds: Self.terminationTimeout)

            // Until the head: that it was heard is all there is to know, and the seed is what lets
            // go of the exchange whether it answered or not.
            _ = try? await deadline.race(seed: task.seed) {
                var iterator = task.response.makeAsyncIterator()

                while let step = try await iterator.next() {
                    if case .download = step {
                        break
                    }
                }
            }

            task.seed()
        }
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

    /// The error to hand over for the failure that ended the last attempt: a "not now" from the
    /// server is a public error of its own, and a failure of the connection is thrown as it is.
    private static func surfaced(_ failure: Error) -> Error {
        guard let response = failure as? ResumableUploadTransientResponse else {
            return failure
        }

        return UploadResumptionError(.serverUnavailable(status: response.status))
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
