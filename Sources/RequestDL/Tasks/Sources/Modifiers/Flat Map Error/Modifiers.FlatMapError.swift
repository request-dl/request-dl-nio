/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /**
     A `TaskModifier` that maps the error of a `Task` to a new `Error` type.

     Use this modifier to transform the error type of a `Task`. The `FlatMapError`
     modifier takes a closure that maps an error of the original task to a new error
     type. The closure is called when the task fails with an error. If the closure
     succeeds, the error is transformed to the new error type. If the closure fails,
     the task fails with the original error.
     */
    public struct FlatMapError<Content: Task>: TaskModifier {

        let transform: (Error) throws -> Void

        /**
         Transforms the result of a `Task` to a new element type.

         - Parameter task: The original `Task`.
         - Throws: An error if the transformation fails.
         - Returns: The result of the transformation.
         */
        public func task(_ task: Content) async throws -> Content.Element {
            do {
                return try await task.result()
            } catch {
                try transform(error)
                throw error
            }
        }
    }
}

extension Task {

    /**
     Returns a `ModifiedTask` with the error-handling behavior specified by the provided closure.

     Use this method to provide a closure that takes an `Error` parameter and returns `Void` to
     be executed when an error occurs during the task.

     Usage Example:

     ```swift
     DataTask { ... }
         .flatMapError { error in
             print("Error encountered during task:", error.localizedDescription)
         }
     ```

     - Parameter transform: A closure that takes an `Error` parameter and
     returns `Void` to be executed when an error occurs.

     - Returns: A `ModifiedTask` with the error-handling behavior specified by the
     `transform` closure.
     */
    public func flatMapError(
        _ transform: @escaping (Error) throws -> Void
    ) -> ModifiedTask<Modifiers.FlatMapError<Self>> {
        modify(Modifiers.FlatMapError(transform: transform))
    }

    /**
     Returns a `ModifiedTask` with the error-handling behavior specified by the provided closure
     and error type.

     Use this method to provide a closure that takes a parameter of the specified error type and returns
     `Void` to be executed when an error of that type occurs during the task.

     Usage Example:
     ```swift
     DataTask { ... }
         .flatMapError(MyCustomError.self) { error in
             print("Custom error encountered during task:", error.localizedDescription)
         }
     ```

     - Parameter type: The type of error to handle.

     - Parameter transform: A closure that takes a parameter of the specified error
     type and returns `Void` to be executed when an error of that type occurs.

     - Returns: A `ModifiedTask` with the error-handling behavior specified by the
     `transform` closure.
     */
    public func flatMapError<Failure: Error>(
        _ type: Failure.Type,
        _ transform: @escaping (Failure) throws -> Void
    ) -> ModifiedTask<Modifiers.FlatMapError<Self>> {
        flatMapError {
            if let error = $0 as? Failure {
                try transform(error)
            }
        }
    }
}
