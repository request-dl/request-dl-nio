/*
 See LICENSE for this package's licensing information.
*/

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
     .result()
 }
 ```
 */
public struct GroupTask<Data: Sequence, Content: Task>: Task where Data.Element: Hashable {

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
    public func result() async throws -> GroupResult<Data.Element, Content.Element> {
        await withTaskGroup(of: (Data.Element, Result<Content.Element, Error>).self) { group in
            for element in data {
                group.addTask {
                    do {
                        return (element, .success(try await map(element).result()))
                    } catch {
                        return (element, .failure(error))
                    }
                }
            }

            var results = GroupResult<Data.Element, Content.Element>()

            for await (key, value) in group {
                results[key] = value
            }

            return results
        }
    }
}

public typealias GroupResult<ID: Hashable, Element> = [ID: Result<Element, Error>]
