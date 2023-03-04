//
//  Interceptors.Logger.swift
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
     An interceptor for logging task responses.

     Use `logInConsole(_:)` method of the `Task` to add an instance of the
     `Interceptors.Logger` interceptor to log task responses.

     Example:

     ```swift
     DataTask { ... }
         .logInConsole(true)
     ```

     - Note: If `isActive` is `true`, it logs task responses in the console.

     - Important: `Interceptors.Logger` can be used as a reference to implement custom interceptors.
     */
    public struct Logger: TaskInterceptor {

        let isLogActive: Bool

        init(_ isActive: Bool) {
            isLogActive = isActive
        }

        /**
        Called when the task response is received.

        - Parameter result: The result of the task execution.
        */
        public func received(_ result: Result<TaskResult<Data>, Error>) {
            guard isLogActive else {
                return
            }

            switch result {
            case .failure(let error):
                print("[REQUEST] Failure: \(error)")
            case .success(let result):
                print("[REQUEST] Success: \(result.response)")
                print("[REQUEST] Data: \(String(data: result.data, encoding: .utf8) ?? "Couldn't decode using UTF8")")
            }
        }
    }
}

extension Task where Element == TaskResult<Data> {

    /**
     Add the `Interceptors.Logger` interceptor to log task responses.

     - Parameter isActive: If `true`, the task responses will be logged in the console.
     - Returns: A new instance of the `InterceptedTask` with `Interceptors.Logger` interceptor.
     */
    public func logInConsole(_ isActive: Bool) -> InterceptedTask<Interceptors.Logger, Self> {
        intercept(Interceptors.Logger(isActive))
    }
}
