//
//  Task.swift
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
 The Task protocol defines an object that makes a request and returns a response asynchronously.

 For URLRequest-based requests, each request is considered as a URLSessionTask that allows the
 monitoring and cancellation of the request through it. For requests using a custom protocol,
 the concept of Task is used to assemble the request and execute it when the `response() function
 is called.

 The associatedtype `Element` represents the type of the expected result of the task.

 - Note: The Task protocol does not specify how the request is made or how the response is processed,
 it only provides a way to execute a request and receive its result asynchronously.
 */
public protocol Task<Element> {

    associatedtype Element

    /**
     Runs the task and gets the result asynchronously.

     - Returns: The expected result of the task wrapped in an asynchronous task.

     - Throws: If there was an error during the execution of the task.
     */
    func response() async throws -> Element
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
        InterceptedTask(self, interceptor)
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
        ModifiedTask(self, modifier)
    }
}
