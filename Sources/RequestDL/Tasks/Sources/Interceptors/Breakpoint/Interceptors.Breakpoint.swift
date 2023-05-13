/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Interceptors {

    /**
     A `TaskInterceptor` that can be used to add a breakpoint to the task's result. The
     breakpoint will stop the task's execution and give control back to the debugger.

     - Note: This should only be used during development and debugging, and not in production
     code.

     Usage

     ```swift
     try await DataTask {
         BaseURL("api.com")
         Path("resource")
     }
     .breakpoint()
     .result()
     ```
     */
    public struct Breakpoint<Element>: TaskInterceptor {

        /**
         Called when a result is received.

         - Parameter result: The `Result` object that represents the result. It contains
         either the result object or an error object.
         */
        public func received(_ result: Result<Element, Error>) {
            #if DEBUG
            Internals.Override.raise(SIGTRAP)
            #endif
        }
    }
}

extension Task {

    /**
     Adds a breakpoint to the task's result. The breakpoint will stop the task's execution and
     give control back to the debugger.

     - Note: This should only be used during development and debugging, and not in
     production code.

     - Returns: An `InterceptedTask` object with the added breakpoint interceptor.
     */
    public func breakpoint() -> InterceptedTask<Interceptors.Breakpoint<Element>, Self> {
        intercept(Interceptors.Breakpoint())
    }
}
