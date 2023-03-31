/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /**
     A task modifier that extracts only the payload from a task result.

     This modifier can be useful in cases where only the payload data is required, and the
     URLResponse is not needed.

     - Note: This modifier is not appropriate when the payload type is `Void`.

     ```
     try await DataTask {
         BaseURL("jsonplaceholder.typicode.com")
         Path("todos/1")
     }
     .decode(Todo.self)
     .extractPayload()
     ```
     */
    public struct ExtractPayload<Content: Task, Element>: TaskModifier where Content.Element == TaskResult<Element> {

        init() {}

        /**
         Modifies the task to extract only the payload from a task result.

         - Parameter task: The task to modify.
         - Returns: A new instance of `Payload` type that contains only the payload data.
         */
        public func task(_ task: Content) async throws -> Element {
            try await task.result().payload
        }
    }
}

extension Task {

    /**
     Modifies the task to ignore the URLResponse and only return the data.

     - Returns: A new modified task that contains only the data.
     */
    public func extractPayload<T>() -> ModifiedTask<Modifiers.ExtractPayload<Self, T>> where Element == TaskResult<T> {
        modify(Modifiers.ExtractPayload())
    }
}
