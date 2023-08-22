/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /**
     A `RequestTaskModifier` that maps the error of a `RequestTask` to a new `Error` type.

     Use this modifier to transform the error type of a `RequestTask`. The `FlatMapError`
     modifier takes a closure that maps an error of the original task to a new error
     type. The closure is called when the task fails with an error. If the closure
     succeeds, the error is transformed to the new error type. If the closure fails,
     the task fails with the original error.
     */
    public struct FlatMapError<Input: Sendable>: RequestTaskModifier {

        // MARK: - Internal properties

        let transform: @Sendable (Error) throws -> Void

        // MARK: - Public methods

        /**
         Transforms the result of a `RequestTask` to a new element type.

         - Parameter task: The original `RequestTask`.
         - Throws: An error if the transformation fails.
         - Returns: The result of the transformation.
         */
        public func body(_ task: Content) async throws -> Input {
            do {
                return try await task.result()
            } catch {
                try transform(error)
                throw error
            }
        }
    }
}

// MARK: - RequestTask extension

extension RequestTask {

    /**
     Returns a `ModifiedTask` with the error-handling behavior specified by the provided closure.

     Use this method to provide a closure that takes an `Error` parameter and returns `Void` to
     be executed when an error occurs during the task.

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
        _ transform: @escaping @Sendable (Error) throws -> Void
    ) -> ModifiedRequestTask<Modifiers.FlatMapError<Element>> {
        modifier(Modifiers.FlatMapError(transform: transform))
    }

    /**
     Returns a `ModifiedTask` with the error-handling behavior specified by the provided closure
     and error type.

     Use this method to provide a closure that takes a parameter of the specified error type and returns
     `Void` to be executed when an error of that type occurs during the task.

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
        _ transform: @escaping @Sendable (Failure) throws -> Void
    ) -> ModifiedRequestTask<Modifiers.FlatMapError<Element>> {
        flatMapError {
            if let error = $0 as? Failure {
                try transform(error)
            }
        }
    }
}
