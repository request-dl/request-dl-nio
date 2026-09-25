//
// See LICENSE for this package's licensing information.
//

extension Interceptors {

    ///
    /// A task interceptor that hands the task's result to a separate closure without changing
    /// the behavior of the main `RequestTask`.
    ///
    /// - Important: The closure runs synchronously, inline, on whatever task/executor is already
    /// resolving the intercepted `RequestTask` -- there is no thread hop or detachment of
    /// execution here despite the name. "Detach" refers to detaching a side effect from the
    /// main result path, not to concurrency: `interceptor(_:)`'s own result is unaffected by
    /// what this closure does, so it can run without changing the task's own outcome.
    ///
    /// ```swift
    /// DataTask { ... }
    ///     .detach { result in
    ///         // Called inline with the task's result.
    ///     }
    /// ```
    ///
    /// > Important: If you don't retain the task returned by this function, the task will be immediately
    /// cancelled when it goes out of scope.
    ///
    public struct Detach<Element: Sendable>: RequestTaskInterceptor {

        // MARK: - Internal properties

        let closure: @Sendable (Result<Element, Error>) -> Void

        // MARK: - Public methods

        ///
        /// A function called with the result of the task.
        ///
        /// - Parameter result: A `Result` object containing either the task's `Element`
        /// or an `Error`.
        ///
        public func output(_ result: Result<Element, Error>) {
            closure(result)
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    ///
    /// Returns a new `InterceptedTask` object that calls `closure` with the task's result,
    /// inline and synchronously, alongside the task's own normal completion.
    ///
    /// - Parameter closure: A closure that is called with the result of the task when it is complete.
    ///
    /// - Returns: A new `InterceptedTask` object.
    ///
    public func detach(
        _ closure: @escaping @Sendable (Result<Element, Error>) -> Void
    ) -> InterceptedRequestTask<Interceptors.Detach<Element>> {
        interceptor(Interceptors.Detach(closure: closure))
    }
}
