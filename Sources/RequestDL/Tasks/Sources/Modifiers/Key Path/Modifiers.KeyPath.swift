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
    public struct KeyPath<Content: Task>: TaskModifier {

        let keyPath: Swift.KeyPath<AbstractKeyPath, String>
        fileprivate let data: (Content.Element) -> Data
        fileprivate let element: (Content.Element, Data) -> Content.Element

        /**
         Transforms the result of the task by extracting a sub-value using the given key path.

         - Parameter task: The task to modify.

         - Returns: A `TaskResult` containing the extracted sub-value.
         */
        public func task(_ task: Content) async throws -> Content.Element {
            let result = try await task.result()

            guard
                let dictionary = try JSONSerialization.jsonObject(
                    with: data(result),
                    options: []
                ) as? [String: Any]
            else { throw KeyPathInvalidDataError() }

            let keyPath = AbstractKeyPath()[keyPath: keyPath]

            guard let value = dictionary[keyPath] else {
                throw KeyPathNotFound(keyPath: keyPath)
            }

            return try element(result, JSONSerialization.data(
                withJSONObject: value,
                options: .fragmentsAllowed
            ))
        }
    }
}

extension Task<TaskResult<Data>> {

    /**
     Returns a new `ModifiedTask` instance that applies the `KeyPath` modifier to the task.

     - Parameter keyPath: The key path to extract the sub-value from the data.

     - Returns: A new `ModifiedTask` instance that applies the `KeyPath` modifier to the task.
     */
    public func keyPath(_ keyPath: KeyPath<AbstractKeyPath, String>) -> ModifiedTask<Modifiers.KeyPath<Self>> {
        modify(Modifiers.KeyPath(
            keyPath: keyPath,
            data: \.payload,
            element: {
                TaskResult(
                    head: $0.head,
                    payload: $1
                )
            }
        ))
    }
}

extension Task<Data> {

    /**
     Returns a new `ModifiedTask` instance that applies the `KeyPath` modifier to the task.

     - Parameter keyPath: The key path to extract the sub-value from the data.

     - Returns: A new `ModifiedTask` instance that applies the `KeyPath` modifier to the task.
     */
    public func keyPath(_ keyPath: KeyPath<AbstractKeyPath, String>) -> ModifiedTask<Modifiers.KeyPath<Self>> {
        modify(Modifiers.KeyPath(
            keyPath: keyPath,
            data: { $0 },
            element: { $1 }
        ))
    }
}
