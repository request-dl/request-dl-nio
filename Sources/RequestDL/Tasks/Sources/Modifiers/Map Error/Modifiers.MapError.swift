/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /// A task modifier that applies a mapping function to the error of the task, allowing for
    /// error handling and transformation.
    public struct MapError<Input: Sendable>: RequestTaskModifier {

        // MARK: - Internal properties

        let transform: @Sendable (Error) throws -> Input

        // MARK: - Public methods

        /**
         A mapping function that transforms the error of the task result to a new error.

         - Parameter task: A `RequestTask` that returns a `TaskResult` containing the error
         to map.
         - Returns: A new error.
         */
        public func body(_ task: Content) async throws -> Input {
            do {
                return try await task.result()
            } catch {
                return try transform(error)
            }
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    /**
     Returns a new `RequestTask` with the error of the original `RequestTask` mapped to a new error.

     - Parameter transform: A mapping function that transforms the error of the
     task result to a new error.
     - Returns: A new `RequestTask` with the mapped error.
     */
    public func mapError(
        _ transform: @escaping @Sendable (Error) throws -> Element
    ) -> ModifiedRequestTask<Modifiers.MapError<Element>> {
        modifier(Modifiers.MapError(transform: transform))
    }
}
