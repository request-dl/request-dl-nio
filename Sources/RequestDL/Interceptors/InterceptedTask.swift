//
//  InterceptedTask.swift
//
//  MIT License
//
//  Copyright (c) RequestDL
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

// swiftlint:disable line_length
/**
 A task that can be intercepted by an `Interceptor` and returns a `Content` object.

 - Interceptor: The type of `Interceptor` that will intercept the task.
 - Content: The type of `Content` that will be returned by the task.

 An `InterceptedTask` conforms to the `Task` protocol and defines a `response()` method that returns a `Content.Element` object. The `response() method can throw an error asynchronously.
 */
public struct InterceptedTask<Interceptor: TaskInterceptor, Content: Task>: Task where Interceptor.Element == Content.Element {

    public typealias Element = Content.Element

    let task: Content
    let interceptor: Interceptor

    init(_ task: Content, _ interceptor: Interceptor) {
        self.task = task
        self.interceptor = interceptor
    }
}

extension InterceptedTask {

    /**
     Returns the response of the task.

     - Throws: An error of type `Error` if the task could not be completed.

     - Returns: An object of type `Element` with the response of the task.
     */
    public func response() async throws -> Element {
        do {
            let response = try await task.response()
            interceptor.received(.success(response))
            return response
        } catch {
            interceptor.received(.failure(error))
            throw error
        }
    }
}
