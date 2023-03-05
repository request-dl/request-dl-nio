//
//  AnyTask.swift
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

/**
 A type-erasing task that wraps another task that has an associated type of Element.
 The AnyTask type forwards its operations to an underlying task object, hiding its
 specific underlying type.

 Example:

 ```swift
 func makeRequest() -> AnyTask<TaskResult<Data>> {
     DataTask {
         BaseURL("google.com")
     }
     .eraseToAnyTask()
 }
 ```
 */
public struct AnyTask<Element>: Task {

    private let wrapper: () async throws -> Element

    init<T: Task>(_ task: T) where T.Element == Element {
        wrapper = { try await task.response() }
    }

    /**
     Returns the result of the wrapped task.

     - Returns: The result of the wrapped task.

     - Throws: If the wrapped task throws an error.
     */
    public func response() async throws -> Element {
        try await wrapper()
    }
}

extension Task {

    /**
     Returns an `AnyTask` instance that wraps `self`.

     - Returns: An `AnyTask` instance that wraps `self`.
     */
    public func eraseToAnyTask() -> AnyTask<Element> {
        .init(self)
    }
}
