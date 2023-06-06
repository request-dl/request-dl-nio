/*
 See LICENSE for this package's licensing information.
*/

import Foundation

extension Modifiers {

    public struct Environment<Input: Sendable>: RequestTaskModifier {

        // MARK: - Internal properties

        let update: @Sendable (inout TaskEnvironmentValues) -> Void

        // MARK: - Public methods

        public func body(_ task: Content) async throws -> Input {
            var task = task
            update(&task.environment)
            return try await task.result()
        }
    }
}

extension RequestTask {

    public func environment<Value: Sendable>(
        _ keyPath: WritableKeyPath<TaskEnvironmentValues, Value>,
        _ value: Value
    ) -> ModifiedRequestTask<Modifiers.Environment<Element>> {
        modifier(Modifiers.Environment {
            $0[keyPath: keyPath] = value
        })
    }
}
