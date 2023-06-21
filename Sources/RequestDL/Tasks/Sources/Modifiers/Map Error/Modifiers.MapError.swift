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
         A mapping function that throws a new error or maps the current error into a valid object.

         - Parameter task: The ``RequestTask`` where its error will be mapped.
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
     Modifies the behavior of the given task by mapping the error into a new error or in a valid result object.

     - Parameter transform: A mapping function that throws a new error or maps the current error into a valid object.
     - Returns: The modified task with the ``Modifiers/MapError`` modifier applied.
     */
    public func mapError(
        _ transform: @escaping @Sendable (Error) throws -> Element
    ) -> ModifiedRequestTask<Modifiers.MapError<Element>> {
        modifier(Modifiers.MapError(transform: transform))
    }
}
