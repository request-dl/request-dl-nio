/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Interceptors {

    /**
     A task interceptor that detaches the task from its context and performs it on another closure.

     - Important: If you don't retain the task returned by this function, the task will be immediately
     cancelled when it goes out of scope.

     Use this interceptor allows you to perform operations on a separate closure without changing
     the behavior of the main `Task`.

     Usage:

     ```swift
     DataTask { ... }
         .detach { result in
             // Result is received on a separate thread
         }
     ```
     */
    public struct Detach<Element>: TaskInterceptor {

        let detachHandler: (Result<Element, Error>) -> Void

        init(detachHandler: @escaping (Result<Element, Error>) -> Void) {
            self.detachHandler = detachHandler
        }

        /**
         A function called with the result of the task.

         - Parameter result: A `Result` object containing either the task's `Element`
         or an `Error`.
         */
        public func received(_ result: Result<Element, Error>) {
            detachHandler(result)
        }
    }
}

extension Task {

    /**
     Returns a new `InterceptedTask` object that runs the current task on a separate thread.

     - Parameter handler: A closure that is called with the result of the task when it is complete.

     - Returns: A new `InterceptedTask` object.
     */
    public func detach(
        _ handler: @escaping (Result<Element, Error>) -> Void
    ) -> InterceptedTask<Interceptors.Detach<Element>, Self> {
        intercept(Interceptors.Detach(detachHandler: handler))
    }
}