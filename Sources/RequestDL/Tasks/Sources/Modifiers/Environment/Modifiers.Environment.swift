/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    /**
     A modifier that updates the environment of `RequestTask` without changing the output.

     > Note: This modifier requires the `RequestTask` to conform to `Sendable`.
     */
    public struct Environment<Input: Sendable>: RequestTaskModifier {

        // MARK: - Internal properties

        let update: @Sendable (inout RequestEnvironmentValues) -> Void

        // MARK: - Public methods

        /**
         Updates the environment of `RequestTask` without changing the output.

         - Parameter task: The original `RequestTask`.
         - Throws: An error thrown by the original task.
         - Returns: The result of the original task.
         */
        public func body(_ task: Content) async throws -> Input {
            var environment = RequestEnvironmentValues.current
            update(&environment)
            return try await RequestEnvironmentValues.$current.withValue(environment) {
                try await task.result()
            }
        }
    }
}

extension RequestTask {

    /**
     Applies an environment modifier to the `RequestTask` using the provided key path and value.

     - Parameters:
        - keyPath: The key path to the environment value.
        - value: The new value to set for the environment value.
     - Returns: A modified `RequestTask` with the applied environment modifier.
     */
    public func environment<Value: Sendable>(
        _ keyPath: WritableKeyPath<RequestEnvironmentValues, Value> & Sendable,
        _ value: Value
    ) -> ModifiedRequestTask<Modifiers.Environment<Element>> {
        modifier(Modifiers.Environment {
            $0[keyPath: keyPath] = value
        })
    }
}

extension RequestTask {

    var environment: RequestEnvironmentValues {
        RequestEnvironmentValues.current
    }
}
