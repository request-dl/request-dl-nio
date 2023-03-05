//
//  ModifiedTask.swift
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
 A type that represents a task that has been modified by a `TaskModifier`.

 A `ModifiedTask` is a `Task` that is created by applying a `TaskModifier` to a base `Task`.

 - Note: The `Element` associated type of the `ModifiedTask` is determined by the `Element`
 associated type of the `TaskModifier`.
 */
public struct ModifiedTask<Modifier: TaskModifier>: Task {

    public typealias Element = Modifier.Element

    let task: Modifier.Body
    let modifier: Modifier

    init(_ task: Modifier.Body, _ modifier: Modifier) {
        self.task = task
        self.modifier = modifier
    }
}

extension ModifiedTask {
    /**
     Returns the response of the task.

     - Throws: An error of type `Error` if the task could not be completed.

     - Returns: An object of type `Element` with the response of the task.
     */
    public func response() async throws -> Element {
        try await modifier.task(task)
    }
}
