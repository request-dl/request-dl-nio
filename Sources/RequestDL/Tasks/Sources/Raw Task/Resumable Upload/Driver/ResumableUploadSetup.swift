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

    // MARK: - Inits

    init(
        dialect: any ResumableUploadDialect,
        maximumAttemptsWithoutProgress: Int = 3,
        delay: UInt64 = 1_000_000_000
    ) {
        precondition(maximumAttemptsWithoutProgress > .zero, "A resumable upload allows at least one attempt")

        self.dialect = dialect
        self.maximumAttemptsWithoutProgress = maximumAttemptsWithoutProgress
        self.delay = delay
    }
}

// MARK: - Environment

private struct ResumableUploadSetupRequestEnvironmentKey: RequestEnvironmentKey {

    static var defaultValue: ResumableUploadSetup? {
        nil
    }
}

extension RequestEnvironmentValues {

    /// Set by ``RequestTask/resumingUploads(using:)``; never touched directly.
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

    /// Makes an upload that loses its connection carry on from where the server stopped, instead
    /// of failing: the server is asked how much of the body it holds, and the rest is sent.
    ///
    /// Not public yet. It is what a public modifier will sit on.
    func resumingUploads(using setup: ResumableUploadSetup) -> AnyTask<Element> {
        ResumingUploadsRequestTask(task: self, setup: setup)
            .eraseToAnyTask()
    }
}
