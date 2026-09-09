//
// See LICENSE for this package's licensing information.
//

extension Internals {

    /// Thrown when a `requireExecutor(_:)` call is pinned to an `Executor` the session's
    /// configuration cannot actually run on.
    ///
    /// `RequestDL`'s public `ExecutorRequirementError` -- the documented, user-facing error --
    /// lives in the `RequestDL` module and cannot be referenced from here, since `RequestDL`
    /// depends on this module rather than the other way around. Callers catch this at the same
    /// site the session bootstraps and rewrap it into `ExecutorRequirementError`.
    package struct IncompatibleExecutorConfigurationError: Error, Sendable {

        package let requiredExecutor: Executor
        package let reasons: [ExecutorIncompatibilityReason]

        package init(requiredExecutor: Executor, reasons: [ExecutorIncompatibilityReason]) {
            self.requiredExecutor = requiredExecutor
            self.reasons = reasons
        }
    }
}
