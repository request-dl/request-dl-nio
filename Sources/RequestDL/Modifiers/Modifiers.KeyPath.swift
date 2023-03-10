/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /**
     A type that modifies the behavior of a `Task`.

     The `KeyPath` modifier allows you to extract a sub-value from the data returned
     by the task using a key path.

     Usage:

     ```swift
     DataTask { ... }
         .keyPath(\.data)
     ```
     */
    public struct KeyPath<Content: Task>: TaskModifier where Content.Element == TaskResult<Data> {

        let keyPath: String

        init(_ keyPath: Swift.KeyPath<AbstractKeyPath, String>) {
            self.keyPath = AbstractKeyPath()[keyPath: keyPath]
        }

        /**
         Transforms the result of the task by extracting a sub-value using the given key path.

         - Parameter task: The task to modify.

         - Returns: A `TaskResult` containing the extracted sub-value.
         */
        public func task(_ task: Content) async throws -> TaskResult<Data> {
            let result = try await task.result()

            guard
                let dictionary = try JSONSerialization.jsonObject(
                    with: result.data,
                    options: []
                ) as? [String: Any]
            else { throw KeyPathInvalidDataError() }

            guard let value = dictionary[keyPath] else {
                throw KeyPathNotFound(keyPath: keyPath)
            }

            return .init(
                response: result.response,
                data: try JSONSerialization.data(
                    withJSONObject: value,
                    options: .fragmentsAllowed
                )
            )
        }
    }
}

extension Task where Element == TaskResult<Data> {

    /**
     Returns a new `ModifiedTask` instance that applies the `KeyPath` modifier to the task.

     - Parameter keyPath: The key path to extract the sub-value from the data.

     - Returns: A new `ModifiedTask` instance that applies the `KeyPath` modifier to the task.
     */
    public func keyPath(_ keyPath: KeyPath<AbstractKeyPath, String>) -> ModifiedTask<Modifiers.KeyPath<Self>> {
        modify(Modifiers.KeyPath(keyPath))
    }
}
