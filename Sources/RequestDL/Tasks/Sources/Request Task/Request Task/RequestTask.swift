/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The RequestTask protocol defines an object that makes a request and returns a result asynchronously.

 For URLRequest-based requests, each request is considered as a URLSessionTask that allows the
 monitoring and cancellation of the request through it. For requests using a custom protocol,
 the concept of RequestTask is used to assemble the request and execute it when the `result()` function
 is called.

 The associatedtype `Element` represents the type of the expected result of the task.

 - Note: The RequestTask protocol does not specify how the request is made or how the result is processed,
 it only provides a way to execute a request and receive its result asynchronously.
 */
public protocol RequestTask<Element>: _RequestTaskInternals {

    associatedtype Element: Sendable

    /**
     Runs the task and gets the result asynchronously.

     - Returns: The expected result of the task wrapped in an asynchronous task.

     - Throws: If there was an error during the execution of the task.
     */
    func result() async throws -> Element
}

// MARK: - RequestTask extension

extension RequestTask {

    /**
     Returns an `InterceptedTask` that executes the original task and intercepts
     its result using the provided `TaskInterceptor`.

     - Parameter interceptor: A `TaskInterceptor` that intercepts the result of the task.

     - Returns: An `InterceptedTask` object that can be used to execute the original task
     and intercept its result.
     */
    @available(*, deprecated, renamed: "interceptor")
    public func intercept<Interceptor: TaskInterceptor>(
        _ interceptor: Interceptor
    ) -> InterceptedTask<Interceptor, Self> {
        InterceptedTask(task: self, interceptor: interceptor)
    }

    /**
     Returns an `InterceptedRequestTask` that executes the original task and intercepts
     its result using the provided `RequestTaskInterceptor`.

     - Parameter interceptor: A `RequestTaskInterceptor` that intercepts the result of the
     task.

     - Returns: An `InterceptedRequestTask` object that can be used to execute the original task
     and intercept its result.
     */
    public func interceptor<Interceptor>(
        _ interceptor: Interceptor
    ) -> InterceptedRequestTask<Interceptor> where Interceptor: RequestTaskInterceptor<Element>  {
        InterceptedRequestTask(
            task: self,
            interceptor: interceptor
        )
    }

    /**
     Returns a `ModifiedTask` that executes the original task and modifies its result using
     the provided `TaskModifier`.

     - Parameter modifier: A `TaskModifier` that modifies the result of the task.

     - Returns: A `ModifiedTask` object that can be used to execute the original task and
     modify its result.
     */
    @available(*, deprecated, renamed: "modifier")
    public func modify<Modifier: TaskModifier>(
        _ modifier: Modifier
    ) -> ModifiedTask<Modifier> where Modifier.Body == Self {
        ModifiedTask(task: self, modifier: modifier)
    }

    /**
     Returns a `ModifiedRequestTask` that executes the original task and modifies its result using
     the provided `RequestTaskModifier`.

     - Parameter modifier: A `RequestTaskModifier` that modifies the result of the task.

     - Returns: A `ModifiedRequestTask` object that can be used to execute the original task and
     modify its result.
     */
    public func modifier<Modifier: RequestTaskModifier>(
        _ modifier: Modifier
    ) -> ModifiedRequestTask<Modifier> where Modifier.Input == Element {
        ModifiedRequestTask(
            task: .init(self),
            modifier: modifier
        )
    }
}

@available(*, deprecated, renamed: "RequestTask")
public typealias Task = RequestTask
