/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /// A task modifier that applies a mapping function to the error of the task, allowing for
    /// error handling and transformation.
    public struct MapError<Content: Task>: TaskModifier {

        let transform: (Error) throws -> Element

        /**
         A mapping function that transforms the error of the task result to a new error.

         - Parameter task: A `Task` that returns a `TaskResult` containing the error to map.
         - Returns: A new error.
         */
        public func task(_ task: Content) async throws -> Content.Element {
            do {
                return try await task.result()
            } catch {
                return try transform(error)
            }
        }
    }
}

extension Task {

    /**
     Returns a new `Task` with the error of the original `Task` mapped to a new error.

     - Parameter transform: A mapping function that transforms the error of the
     task result to a new error.
     - Returns: A new `Task` with the mapped error.
     */
    public func mapError(
        _ transform: @escaping (Error) throws -> Element
    ) -> ModifiedTask<Modifiers.MapError<Self>> {
        modify(Modifiers.MapError(transform: transform))
    }
}
