/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The ``RequestTask`` protocol defines an object that makes a request and returns a result asynchronously.

 For URLRequest-based requests, each request is considered as a URLSessionTask that allows the
 monitoring and cancellation of the request through it. For requests using a custom protocol,
 the concept of ``RequestTask`` is used to assemble the request and execute it when the ``RequestTask/result()``function is called.

 The associatedtype `Element` represents the type of the expected result of the task.

 > Note: The ``RequestTask`` protocol does not specify how the request is made or how the result is processed, it only provides a way to execute a request and receive its result asynchronously.
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
     Returns an ``InterceptedRequestTask`` that executes the base task and intercepts
     its result using the provided ``RequestTaskInterceptor``.

     - Parameter interceptor: A ``RequestTaskInterceptor`` that intercepts the result of the
     task.

     - Returns: A ``RequestTaskInterceptor`` with result being intercepted.
     */
    public func interceptor<Interceptor>(
        _ interceptor: Interceptor
    ) -> InterceptedRequestTask<Interceptor> where Interceptor: RequestTaskInterceptor<Element> {
        InterceptedRequestTask(
            task: self,
            interceptor: interceptor
        )
    }

    /**
     Returns a ``ModifiedRequestTask`` that executes the base task and modifies its result using
     the provided ``RequestTaskModifier``.

     - Parameter modifier: A ``RequestTaskModifier`` that modifies the result of the task.

     - Returns: A ``ModifiedRequestTask`` with new result type.
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
