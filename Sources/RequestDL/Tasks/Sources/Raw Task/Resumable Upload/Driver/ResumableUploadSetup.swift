//
// See LICENSE for this package's licensing information.
//

/// How an upload is made resumable: the protocol it speaks, and how hard it tries to carry on.
struct ResumableUploadSetup: Sendable {

    // MARK: - Internal properties

    let dialect: any ResumableUploadDialect

    /// Attempts in a row that may end without the server holding a single new byte before the
    /// upload fails for good. Any progress starts the count over, so a long upload over a flaky
    /// network isn't capped while a server that keeps failing is given up on.
    let maximumAttemptsWithoutProgress: Int

    /// Nanoseconds to wait before each attempt.
    let delay: UInt64

    /// What is done on the server when the request is cancelled.
    let cancellation: UploadCancellation

    // MARK: - Inits

    init(
        dialect: any ResumableUploadDialect,
        maximumAttemptsWithoutProgress: Int = 3,
        delay: UInt64 = 1_000_000_000,
        cancellation: UploadCancellation = .terminate
    ) {
        precondition(maximumAttemptsWithoutProgress > .zero, "A resumable upload allows at least one attempt")

        self.dialect = dialect
        self.maximumAttemptsWithoutProgress = maximumAttemptsWithoutProgress
        self.delay = delay
        self.cancellation = cancellation
    }
}

// MARK: - Environment

private struct ResumableUploadSetupRequestEnvironmentKey: RequestEnvironmentKey {

    static var defaultValue: ResumableUploadSetup? {
        nil
    }
}

extension RequestEnvironmentValues {

    /// Set by ``RequestTask/resumingUploads(_:maximumAttemptsWithoutProgress:delay:onCancellation:)``;
    /// never touched directly.
    ///
    /// `RawTask` is the only thing that reads it, once it has the client an execution runs on.
    var resumableUploadSetup: ResumableUploadSetup? {
        get { self[ResumableUploadSetupRequestEnvironmentKey.self] }
        set { self[ResumableUploadSetupRequestEnvironmentKey.self] = newValue }
    }
}

// MARK: - Modifier

/// Backs `resumingUploads(using:)`. Sets the setup on the environment instead of acting on the task
/// itself: only `RawTask`, sitting under whatever chain of modifiers wraps it, runs a transfer.
struct ResumingUploadsRequestTask<Task: RequestTask>: RequestTask {

    // MARK: - Internal properties

    let task: Task
    let setup: ResumableUploadSetup

    // MARK: - Internal methods

    func _result(environment: RequestEnvironmentValues) async throws -> Task.Element {
        var environment = environment
        environment.resumableUploadSetup = setup
        return try await task._result(environment: environment)
    }
}

extension RequestTask {

    ///
    /// Makes an upload that loses its connection carry on from where the server stopped, instead of
    /// failing: the server is asked how much of the body it holds, and the rest is sent.
    ///
    /// ```swift
    /// try await UploadTask {
    ///     BaseURL("https://example.com")
    ///     Path("/files/report.bin")
    ///     RequestMethod(.put)
    ///     Payload(url: reportURL)
    /// }
    /// .resumingUploads(.tus)
    /// .collectData()
    /// .result()
    /// ```
    ///
    /// Off by default, and never negotiated: the server has to speak the protocol that is asked for
    /// (``IETFResumableUpload`` and ``TUSResumableUpload`` are the two there are), since an upload
    /// that is created for one that doesn't isn't one the server can be asked about afterwards.
    ///
    /// The upload is created first, which is one more request, and the body is then sent to it. When
    /// the connection is lost, or the server answers that it can't say where the upload stands right
    /// now, the request waits while a ``RequestController`` it is attached to is suspended, waits
    /// `delay`, asks the server how much it holds, and sends the rest. The response to the request
    /// that completes the upload is the response of the upload: its head, and its body.
    ///
    /// - Parameters:
    ///   - protocol: The protocol to speak. Defaults to ``IETFResumableUpload``, written
    ///   `.ietf`.
    ///   - maximumAttemptsWithoutProgress: How many attempts after a loss may end without the
    ///   server holding a single new byte before the upload fails for good, with the failure of
    ///   the last one. Any progress starts the count over, so a long upload over a flaky network
    ///   isn't capped, while a server that keeps failing is given up on. Values below one are
    ///   treated as one.
    ///   - delay: Seconds to wait before each attempt. Negative values are treated as zero.
    ///   - onCancellation: What is done on the server when the request is cancelled. Defaults to
    ///   ``UploadCancellation/terminate``.
    /// - Returns: A task that produces this task's actual result, exactly as ``result()`` would.
    ///
    /// - Important: Only a request with a body is an upload. A body that is compressed as it is
    /// sent is compressed first, once, so that what the server holds means the same bytes for
    /// every attempt: in memory up to 8 MiB, in a temporary file beyond that. What upload progress
    /// counts is what crossed the network, the bytes that had to be sent again included, so it
    /// can pass the size of the body after a retry. Nothing is kept between launches of the
    /// application, and an upload that is abandoned (a request that is cancelled without the
    /// server being told, an application that is closed) is left to the server to expire.
    ///
    public func resumingUploads<Protocol: ResumableUploadProtocol>(
        _ protocol: Protocol,
        maximumAttemptsWithoutProgress: Int = 3,
        delay: Double = 1,
        onCancellation: UploadCancellation = .terminate
    ) -> AnyTask<Element> {
        let nanoseconds = (max(delay, .zero) * 1_000_000_000).rounded()

        let setup = ResumableUploadSetup(
            dialect: `protocol`.dialect,
            maximumAttemptsWithoutProgress: max(1, maximumAttemptsWithoutProgress),
            delay: nanoseconds >= Double(UInt64.max) ? .max : UInt64(nanoseconds),
            cancellation: onCancellation
        )

        return resumingUploads(using: setup)
    }

    /// Makes an upload resumable with the IETF working group's protocol, ``IETFResumableUpload``.
    ///
    /// See ``resumingUploads(_:maximumAttemptsWithoutProgress:delay:onCancellation:)``.
    public func resumingUploads(
        maximumAttemptsWithoutProgress: Int = 3,
        delay: Double = 1,
        onCancellation: UploadCancellation = .terminate
    ) -> AnyTask<Element> {
        resumingUploads(
            .ietf,
            maximumAttemptsWithoutProgress: maximumAttemptsWithoutProgress,
            delay: delay,
            onCancellation: onCancellation
        )
    }

    func resumingUploads(using setup: ResumableUploadSetup) -> AnyTask<Element> {
        ResumingUploadsRequestTask(task: self, setup: setup)
            .eraseToAnyTask()
    }
}
