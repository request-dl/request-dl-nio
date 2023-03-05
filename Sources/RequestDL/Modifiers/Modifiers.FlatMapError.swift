//
//  Modifiers.FlatMapError.swift
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

        // swiftlint:disable nesting
        public typealias Element = Content.Element

        let flatMapErrorHandler: (Error) throws -> Void

        init(flatMapErrorHandler: @escaping (Error) throws -> Void) {
            self.flatMapErrorHandler = flatMapErrorHandler
        }

        /**
         Transforms the result of a `Task` to a new element type.

         - Parameter task: The original `Task`.
         - Throws: An error if the transformation fails.
         - Returns: The result of the transformation.
         */
        public func task(_ task: Content) async throws -> Element {
            do {
                return try await task.response()
            } catch {
                try flatMapErrorHandler(error)
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

     - Parameter flatMapErrorHandler: A closure that takes an `Error` parameter and
     returns `Void` to be executed when an error occurs.

     - Returns: A `ModifiedTask` with the error-handling behavior specified by the
     `flatMapErrorHandler` closure.
     */
    public func flatMapError(
        _ flatMapErrorHandler: @escaping (Error) throws -> Void
    ) -> ModifiedTask<Modifiers.FlatMapError<Self>> {
        modify(Modifiers.FlatMapError(flatMapErrorHandler: flatMapErrorHandler))
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

     - Parameter flatMapErrorHandler: A closure that takes a parameter of the specified error
     type and returns `Void` to be executed when an error of that type occurs.

     - Returns: A `ModifiedTask` with the error-handling behavior specified by the
     `flatMapErrorHandler` closure.
     */
    public func flatMapError<Failure: Error>(
        _ type: Failure.Type,
        _ flatMapErrorHandler: @escaping (Failure) throws -> Void
    ) -> ModifiedTask<Modifiers.FlatMapError<Self>> {
        flatMapError {
            if let error = $0 as? Failure {
                try flatMapErrorHandler(error)
            }
        }
    }
}
