//
//  GroupTask.swift
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
 A task that groups multiple tasks that operate on an element of the same collection type.

 You can use `GroupTask` to create a single task that encapsulates an array of tasks that
 operate on each element of the same collection type.

 Usage:

 ```swift
 func makeMultipleRequest() async throws -> [GroupResult<Int, TaskResult<Data>>] {
     try await GroupTask([0, 1, 2, 3]) { index in
         DataTask {
             BaseURL("google.com")
             Path("results")
             Query(index, forKey: "page")
         }
     }
     .response()
 }
 ```
 */
public struct GroupTask<Data: Collection, Content: Task>: Task {

    private let data: Data
    private let map: (Data.Element) -> Content

    /**
     Initializes a `GroupTask` instance.

     - Parameters:
        - data: The type of the collection that contains the elements.
        - content: The closure map function that transform each element of data into of task.
     */
    public init(_ data: Data, content: @escaping (Data.Element) -> Content) {
        self.data = data
        self.map = content
    }
}

extension GroupTask {

    /**
    Retrieves the results of the task group that encapsulates the results of each individual task.

    - Returns: An array of `GroupResult` that encapsulates the result of each individual task.
    - Throws: Error if any of the individual tasks encounters an error during execution.
    */
    public func response() async throws -> [GroupResult<Data.Element, Content.Element>] {
        try await withThrowingTaskGroup(of: GroupResult<Data.Element, Content.Element>.self) { group in
            for element in data {
                group.addTask {
                    let data = try await map(element).response()
                    return .init(id: element, result: data)
                }
            }

            var stack = [GroupResult<Data.Element, Content.Element>]()

            for try await element in group {
                stack.append(element)
            }

            return stack
        }
    }
}

/**
 Represents the result of a task that has been executed as part of a `GroupTask`.

 `GroupResult` is a simple struct that encapsulates two pieces of data: an ID value and the result
 of the associated task execution. The ID value represents the original element from the collection
 that the associated task was created from.
 */
public struct GroupResult<ID, Element> {

    /// The ID value representing the original element from the collection.
    public let id: ID

    /// The result of the associated task execution.
    public let result: Element

    init(id: ID, result: Element) {
        self.id = id
        self.result = result
    }
}
