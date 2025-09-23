//
//  File.swift
//  request-dl
//
//  Created by Brenno de Moura on 23/09/25.
//

import Foundation

/**
 A property wrapper that provides safe, dynamic access to task-scoped environment values.

 Use `@TaskEnvironment` to inject dependencies or configuration into types that execute within
 an asynchronous task context. The wrapped value is resolved at access time from the active
 task environment, allowing different tasks to operate with isolated or customized environments.

 - Note: The wrapped `Value` type must conform to `Sendable` to ensure safe usage across concurrency boundaries.

 ### Basic Usage:

 Declare a property using `@TaskEnvironment` with a key path to the desired environment value:

 ```swift
 struct NumberTask: RequestTask {
     @TaskEnvironment(\.number) var number

     func result() async throws -> Int {
        return number
     }
 }
 ```

 Configure the environment for a task using the `.environment(_:_:)` modifier before execution:

 ```swift
 let number = 2
 let numberTask = NumberTask()

 let value = try await numberTask
     .environment(\.number, number)
     .result()
 ```

 ### How It Works:
 - The value is resolved dynamically each time the property is accessed.
 - Each task may have its own environment, making this ideal for testing, dependency injection,
 or context-specific behavior.
 - No caching or storage — every access reflects the environment state at that moment.

 ### Requirements:
 - `Value` must conform to `Sendable`.
 - The task must have an active environment configured (typically via an `.environment` modifier or equivalent).

 ## See Also
 
 - ``RequestDL/TaskEnvironmentValues``
 */
@propertyWrapper
public struct TaskEnvironment<Value: Sendable>: Sendable {

    // MARK: - Public Properties

    /// The value provided by the current task’s environment.
    ///
    /// This property dynamically retrieves the value associated with the key path specified at initialization.
    ///
    /// - Returns: The environment-provided value of type `Value`.
    public var wrappedValue: Value {
        keyPath(TaskEnvironmentValues.current)
    }

    // MARK: - Private Properties

    private let keyPath: @Sendable (TaskEnvironmentValues) -> Value

    // MARK: - Initializers

    /// Creates a new `TaskEnvironment` wrapper for the given environment key path.
    ///
    /// - Parameter keyPath: A `KeyPath` identifying the desired value in the task environment.
    ///                      Must be `Sendable` to ensure thread safety.
    public init(_ keyPath: KeyPath<TaskEnvironmentValues, Value> & Sendable) {
        self.keyPath = {
            $0[keyPath: keyPath]
        }
    }
}
