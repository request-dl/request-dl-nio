//
//  Interceptors.Breakpoint.swift
//
//  MIT License
//
//  Copyright (c) 2022 RequestDL
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Foundation

extension Interceptors {

    /**
     A `TaskInterceptor` that can be used to add a breakpoint to the task's response. The
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
     .response()
     ```
     */
    public struct Breakpoint<Element>: TaskInterceptor {

        init() {}

        /**
         Called when a response is received.

         - Parameter result: The `Result` object that represents the response. It contains
         either the response object or an error object.
         */
        public func received(_ result: Result<Element, Error>) {
            raise(SIGTRAP)
        }
    }
}

extension Task {

    /**
     Adds a breakpoint to the task's response. The breakpoint will stop the task's execution and
     give control back to the debugger.

     - Note: This should only be used during development and debugging, and not in
     production code.

     - Returns: An `InterceptedTask` object with the added breakpoint interceptor.
     */
    public func breakpoint() -> InterceptedTask<Interceptors.Breakpoint<Element>, Self> {
        intercept(Interceptors.Breakpoint())
    }
}
