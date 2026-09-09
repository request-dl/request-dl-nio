//
// See LICENSE for this package's licensing information.
//

/// The ``RequestTask`` protocol defines an object that makes a request and returns a result asynchronously.
///
/// For URLRequest-based requests, each request is considered as a URLSessionTask that allows the
/// monitoring and cancellation of the request through it. For requests using a custom protocol,
/// the concept of ``RequestTask`` is used to assemble the request and execute it when the
/// ``RequestTask/result()``function is called.
///
/// The associatedtype `Element` represents the type of the expected result of the task.
///
/// > Note: The ``RequestTask`` protocol does not specify how the request is made or how the result is
/// processed, it only provides a way to execute a request and receive its result asynchronously.
public protocol RequestTask<Element>: Sendable {

    associatedtype Element: Sendable

    ///
    /// Runs the task and gets the result asynchronously.
    ///
    /// - Returns: The expected result of the task wrapped in an asynchronous task.
    ///
    /// - Throws: If there was an error during the execution of the task.
    ///
    func result() async throws -> Element

    /// This method is used internally and should not be called directly.
    @_spi(Private)
    func _result(environment: RequestEnvironmentValues) async throws -> Element
}

// MARK: - RequestTask default result / _result

extension RequestTask {

    /// Runs the task with a fresh, empty environment -- the entry point for a task that isn't
    /// nested inside another task's `.environment()`/`_result(environment:)` call.
    ///
    /// Conformers that only need `result()` to do real work off of `environment` (`RawTask`,
    /// `MockedTask`, wrapper types forwarding to an inner task, ...) implement `_result(environment:)`
    /// instead and get this for free. Conformers with no use for `environment` at all (a plain
    /// custom `RequestTask`) implement `result()` directly instead and get `_result(environment:)`
    /// for free -- see its own default below. Implementing neither recurses forever; every
    /// conformer needs at least one real implementation.
    public func result() async throws -> Element {
        try await _result(environment: RequestEnvironmentValues())
    }

    /// This method is used internally and should not be called directly.
    ///
    /// The default implementation threads `environment` into any `@RequestEnvironment`-marked
    /// stored property found via reflection -- the same mechanism `@RequestEnvironment` already
    /// uses -- and then calls the ordinary `result()`. Conformers that need `environment` to do
    /// real work (building a request, mocking a response, ...) override this instead of relying
    /// on the default.
    @_spi(Private)
    public func _result(environment: RequestEnvironmentValues) async throws -> Element {
        for child in DynamicValueMirror(self)() {
            (child.value as? DynamicEnvironment)?.update(environment)
        }

        return try await result()
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    ///
    /// Returns an ``InterceptedRequestTask`` that executes the base task and intercepts
    /// its result using the provided ``RequestTaskInterceptor``.
    ///
    /// - Parameter interceptor: A ``RequestTaskInterceptor`` that intercepts the result of the
    /// task.
    ///
    /// - Returns: A ``RequestTaskInterceptor`` with result being intercepted.
    ///
    public func interceptor<Interceptor>(
        _ interceptor: Interceptor
    ) -> InterceptedRequestTask<Interceptor> where Interceptor: RequestTaskInterceptor<Element> {
        InterceptedRequestTask(
            task: self,
            interceptor: interceptor
        )
    }

    ///
    /// Returns a ``ModifiedRequestTask`` that executes the base task and modifies its result using
    /// the provided ``RequestTaskModifier``.
    ///
    /// - Parameter modifier: A ``RequestTaskModifier`` that modifies the result of the task.
    ///
    /// - Returns: A ``ModifiedRequestTask`` with new result type.
    ///
    public func modifier<Modifier: RequestTaskModifier>(
        _ modifier: Modifier
    ) -> ModifiedRequestTask<Modifier> where Modifier.Input == Element {
        ModifiedRequestTask(
            task: .init(self),
            modifier: modifier
        )
    }
}
