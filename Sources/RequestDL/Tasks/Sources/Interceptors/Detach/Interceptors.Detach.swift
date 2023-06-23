/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Interceptors {

    /**
     A task interceptor that detaches the task from its context and performs it on another closure.

     Use this interceptor allows you to perform operations on a separate closure without changing
     the behavior of the main `RequestTask`.

     ```swift
     DataTask { ... }
         .detach { result in
             // Result is received on a separate thread
         }
     ```

     > Important: If you don't retain the task returned by this function, the task will be immediately
     cancelled when it goes out of scope.
     */
    public struct Detach<Element: Sendable>: RequestTaskInterceptor {

        // MARK: - Internal properties

        let closure: @Sendable (Result<Element, Error>) -> Void

        // MARK: - Public methods

        /**
         A function called with the result of the task.

         - Parameter result: A `Result` object containing either the task's `Element`
         or an `Error`.
         */
        public func output(_ result: Result<Element, Error>) {
            closure(result)
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    /**
     Returns a new `InterceptedTask` object that runs the current task on a separate thread.

     - Parameter closure: A closure that is called with the result of the task when it is complete.

     - Returns: A new `InterceptedTask` object.
     */
    public func detach(
        _ closure: @escaping @Sendable (Result<Element, Error>) -> Void
    ) -> InterceptedRequestTask<Interceptors.Detach<Element>> {
        interceptor(Interceptors.Detach(closure: closure))
    }
}
