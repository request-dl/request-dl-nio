//
//  Interceptors.Detach.swift
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
