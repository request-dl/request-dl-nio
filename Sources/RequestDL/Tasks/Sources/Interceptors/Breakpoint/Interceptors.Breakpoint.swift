/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Interceptors {

    /**
     A `RequestTaskInterceptor` that can be used to add a breakpoint to the task's result. The
     breakpoint will stop the task's execution and give control back to the debugger.

     ```swift
     try await DataTask {
         BaseURL("api.com")
         Path("resource")
     }
     .breakpoint()
     .result()
     ```

     > Note: This should only be used during development and debugging, and not in production
     code.
     */
    public struct Breakpoint<Element: Sendable>: RequestTaskInterceptor {

        /**
         Called when a result is received.

         - Parameter result: The `Result` object that represents the result. It contains
         either the result object or an error object.
         */
        public func output(_ result: Result<Element, Error>) {
            #if DEBUG
            Internals.Override.raise(SIGTRAP)
            #endif
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    /**
     Adds a breakpoint to the task's result. The breakpoint will stop the task's execution and
     give control back to the debugger.

     > Note: This should only be used during development and debugging, and not in
     production code.

     - Returns: An `InterceptedTask` object with the added breakpoint interceptor.
     */
    public func breakpoint() -> InterceptedRequestTask<Interceptors.Breakpoint<Element>> {
        interceptor(Interceptors.Breakpoint())
    }
}
