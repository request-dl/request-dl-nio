//
//  TaskInterceptor.swift
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

/**
 Protocol for intercepting and handling results from tasks.

 Define the protocol with a generic type `Element`. The generic type represents the element
 that the task will return.

 Use the `received` method to handle the result of the task with a
 `Result<Element, Error>` parameter.

 - Note: This protocol can be used as a base for creating custom interceptors for tasks.

 Example usage:

 ```swift
 struct MyInterceptor: TaskInterceptor {
     typealias Element = String

     func received(_ result: Result<Element, Error>) {
         switch result {
         case .success(let string):
             print("Intercepted task with string result: \(string)")
         case .failure(let error):
             print("Intercepted task with error: \(error.localizedDescription)")
         }
     }
 }
 ```

 - Warning: It is the responsibility of the interceptor to handle errors that may occur
 during the task execution.
 */
public protocol TaskInterceptor {

    associatedtype Element

    /**
     This method is part of the `TaskInterceptor` protocol, which allows an object to
     intercept and handle the result of a task execution.

     The `received` method is called when the task completes, and receives a `Result`
     object containing either a successful `Element` result or an `Error`.

     - Parameter result: A `Result` object containing either a successful `Element`
     result or an `Error`.
     */
    func received(_ result: Result<Element, Error>)
}
