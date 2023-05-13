/*
 See LICENSE for this package's licensing information.
*/

import Foundation

/**
 The Task protocol defines an object that makes a request and returns a result asynchronously.

 For URLRequest-based requests, each request is considered as a URLSessionTask that allows the
 monitoring and cancellation of the request through it. For requests using a custom protocol,
 the concept of Task is used to assemble the request and execute it when the `result()` function
 is called.

 The associatedtype `Element` represents the type of the expected result of the task.

 - Note: The Task protocol does not specify how the request is made or how the result is processed,
 it only provides a way to execute a request and receive its result asynchronously.
 */
@RequestActor
public protocol Task<Element> {

    associatedtype Element

    /**
     Runs the task and gets the result asynchronously.

     - Returns: The expected result of the task wrapped in an asynchronous task.

     - Throws: If there was an error during the execution of the task.
     */
    func result() async throws -> Element
}

extension Task {

    /**
     Returns an `InterceptedTask` that executes the original task and intercepts
     its result using the provided `TaskInterceptor`.

     - Parameter interceptor: A `TaskInterceptor` that intercepts the result of the task.

     - Returns: An `InterceptedTask` object that can be used to execute the original task
     and intercept its result.
     */
    public func intercept<Interceptor: TaskInterceptor>(
        _ interceptor: Interceptor
    ) -> InterceptedTask<Interceptor, Self> {
        InterceptedTask(task: self, interceptor: interceptor)
    }

    /**
     Returns a `ModifiedTask` that executes the original task and modifies its result using
     the provided `TaskModifier`.

     - Parameter modifier: A `TaskModifier` that modifies the result of the task.

     - Returns: A `ModifiedTask` object that can be used to execute the original task and
     modify its result.
     */
    public func modify<Modifier: TaskModifier>(
        _ modifier: Modifier
    ) -> ModifiedTask<Modifier> where Modifier.Body == Self {
        ModifiedTask(task: self, modifier: modifier)
    }
}
