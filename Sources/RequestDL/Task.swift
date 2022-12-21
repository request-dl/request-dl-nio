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
 The Task defines the objects that make the request.

 For the URLRequest, each request is considered as a URLSessionDownloadTask
 that allows the monitoring and cancellation of the request through it. In the case of
 the protocol, the concept of Task is used to assemble the request and execute it when
 the onResponse function is called.
 */
public protocol Task {

    associatedtype Element

    /// Runs the task and gets the result asynchronously
    func response() async throws -> Element
}

extension Task {

    /// Adds a Interceptor to obtain the result of the call separately
    public func intercept<Interceptor: TaskInterceptor>(
        _ interceptor: Interceptor
    ) -> InterceptedTask<Interceptor, Self> {
        InterceptedTask(self, interceptor)
    }

    /// Adds a Modifier to process and change the result of the call
    public func modify<Modifier: TaskModifier>(
        _ modifier: Modifier
    ) -> ModifiedTask<Modifier> where Modifier.Body == Self {
        ModifiedTask(self, modifier)
    }
}
