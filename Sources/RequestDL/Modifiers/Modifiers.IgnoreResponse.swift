//
//  Modifiers.IgnoreResponse.swift
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

extension Modifiers {

    /**
     A task modifier that ignores the response data and only returns the data.

     This modifier can be useful in cases where the response is not needed, but
     only the data.
     */
    public struct IgnoreResponse<Content: Task, Element>: TaskModifier where Content.Element == TaskResult<Element> {

        init() {}

        /**
         Modifies the task to ignore the response and only return the data.

         - Parameter task: The task to modify.

         - Returns: A new instance of `Element` type that contains only the data.
         */
        public func task(_ task: Content) async throws -> Element {
            try await task.response().data
        }
    }
}

extension Task {

    /**
     Modifies the task to ignore the response and only return the data.

     - Returns: A new modified task that contains only the data.
     */
    public func ignoreResponse<T>() -> ModifiedTask<Modifiers.IgnoreResponse<Self, T>> where Element == TaskResult<T> {
        modify(Modifiers.IgnoreResponse())
    }
}
