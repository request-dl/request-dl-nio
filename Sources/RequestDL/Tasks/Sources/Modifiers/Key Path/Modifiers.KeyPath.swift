/*
 See LICENSE for this package's licensing information.
*/

#if canImport(Darwin)
import Foundation
#else
@preconcurrency import Foundation
#endif

extension Modifiers {

    /**
     A type that modifies the behavior of a `RequestTask`.

     The `KeyPath` modifier allows you to extract a sub-value from the data returned
     by the task using a key path.

     Usage:

     ```swift
     DataTask { ... }
         .keyPath(\.data)
     ```
     */
    public struct KeyPath<Input: Sendable>: RequestTaskModifier {

        // MARK: - Internal properties

        let keyPath: @Sendable (AbstractKeyPath) -> String

        // MARK: - Private properties

        fileprivate let data: @Sendable (Input) -> Data
        fileprivate let element: @Sendable (Input, Data) -> Input

        // MARK: - Public methods

        /**
         Transforms the result of the task by extracting a sub-value using the given key path.

         - Parameter task: The task to modify.

         - Returns: A `TaskResult` containing the extracted sub-value.
         */
        public func body(_ task: Content) async throws -> Input {
            let result = try await task.result()

            guard
                let dictionary = try JSONSerialization.jsonObject(
                    with: data(result),
                    options: []
                ) as? [String: Any]
            else { throw KeyPathInvalidDataError() }

            let keyPath = keyPath(AbstractKeyPath())

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

// MARK: - RequestTask extension

extension RequestTask<TaskResult<Data>> {

    /**
     Returns a new `ModifiedTask` instance that applies the `KeyPath` modifier to the task.

     - Parameter keyPath: The key path to extract the sub-value from the data.

     - Returns: A new `ModifiedTask` instance that applies the `KeyPath` modifier to the task.
     */
    public func keyPath(
        _ keyPath: KeyPath<AbstractKeyPath, String>
    ) -> ModifiedRequestTask<Modifiers.KeyPath<Element>> {
        modifier(Modifiers.KeyPath(
            keyPath: { $0[keyPath: keyPath] },
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

extension RequestTask<Data> {

    /**
     Returns a new `ModifiedTask` instance that applies the `KeyPath` modifier to the task.

     - Parameter keyPath: The key path to extract the sub-value from the data.

     - Returns: A new `ModifiedTask` instance that applies the `KeyPath` modifier to the task.
     */
    public func keyPath(
        _ keyPath: KeyPath<AbstractKeyPath, String>
    ) -> ModifiedRequestTask<Modifiers.KeyPath<Element>> {
        modifier(Modifiers.KeyPath(
            keyPath: { $0[keyPath: keyPath] },
            data: { $0 },
            element: { $1 }
        ))
    }
}
