/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /// A task modifier that applies a mapping function to the error of the task, allowing for
    /// error handling and transformation.
    public struct MapError<Content: Task>: TaskModifier {

        // swiftlint:disable nesting
        public typealias Element = Content.Element

        let mapErrorHandler: (Error) throws -> Element

        init(mapErrorHandler: @escaping (Error) throws -> Element) {
            self.mapErrorHandler = mapErrorHandler
        }

        /**
         A mapping function that transforms the error of the task result to a new error.

         - Parameter task: A `Task` that returns a `TaskResult` containing the error to map.
         - Returns: A new error.
         */
        public func task(_ task: Content) async throws -> Element {
            do {
                return try await task.result()
            } catch {
                return try mapErrorHandler(error)
            }
        }
    }
}

extension Task {

    /**
     Returns a new `Task` with the error of the original `Task` mapped to a new error.

     - Parameter mapErrorHandler: A mapping function that transforms the error of the
     task result to a new error.
     - Returns: A new `Task` with the mapped error.
     */
    public func mapError(
        _ mapErrorHandler: @escaping (Error) throws -> Element
    ) -> ModifiedTask<Modifiers.MapError<Self>> {
        modify(Modifiers.MapError(mapErrorHandler: mapErrorHandler))
    }
}
